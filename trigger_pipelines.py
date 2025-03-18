import boto3
import argparse
import time
import logging
import json
import os  # Import os module to delete files
from threading import Thread, Lock
from pathlib import Path
from datetime import datetime

# Generate a unique log filename with a timestamp
log_filename = f"pipeline_execution_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

# Configure logging to both console and file
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_filename),  # Log to a unique file
        logging.StreamHandler()            # Log to console
    ]
)

# Initialize boto3 client for CodePipeline
client = boto3.client('codepipeline')

# Global variables to track pipeline statuses
successful_pipelines = []
failed_pipelines = []
lock = Lock()

# File to store pipeline state
STATE_FILE = "pipeline_state.json"

def load_state():
    """Load the pipeline state from a file."""
    if Path(STATE_FILE).exists():
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    return {
        "triggered_pipelines": [],
        "successful_pipelines": [],
        "failed_pipelines": [],
        "in_progress_pipelines": {}
    }

def save_state(state):
    """Save the pipeline state to a file."""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)

def read_pipeline_names(file_path):
    """Read pipeline names from a file."""
    with open(file_path, 'r') as f:
        return [line.strip() for line in f if line.strip()]

def trigger_pipeline(pipeline_name):
    """Trigger a CodePipeline and return the execution ID."""
    try:
        response = client.start_pipeline_execution(name=pipeline_name)
        execution_id = response['pipelineExecutionId']
        logging.info(f"Triggered pipeline: {pipeline_name} with execution ID: {execution_id}")
        time.sleep(5)  # Allow AWS time to initialize the pipeline execution
        return execution_id
    except Exception as e:
        logging.error(f"Failed to trigger pipeline {pipeline_name}: {str(e)}")
        with lock:
            failed_pipelines.append(pipeline_name)
        return None

def monitor_pipeline(pipeline_name, execution_id, state):
    """Monitor the status of a CodePipeline execution."""
    start_time = datetime.utcnow().isoformat()
    state["in_progress_pipelines"][pipeline_name]["start_time"] = start_time
    save_state(state)

    logging.info(f"Started monitoring pipeline: {pipeline_name} (Execution ID: {execution_id})")

    retry_count = 5  # Number of retries before giving up
    while retry_count > 0:
        try:
            response = client.get_pipeline_execution(
                pipelineName=pipeline_name,
                pipelineExecutionId=execution_id
            )
            status = response['pipelineExecution']['status']
            
            if status in ['Succeeded', 'Failed']:
                stop_time = datetime.utcnow().isoformat()
                with lock:
                    if status == 'Succeeded':
                        successful_pipelines.append(pipeline_name)
                        logging.info(f"Pipeline {pipeline_name} completed successfully.")
                    else:
                        failed_pipelines.append(pipeline_name)
                        logging.error(f"Pipeline {pipeline_name} failed.")
                # Update state
                pipeline_data = state["in_progress_pipelines"].pop(pipeline_name)
                pipeline_data["pipeline_name"] = pipeline_name  # Add pipeline name to the data
                pipeline_data["stop_time"] = stop_time
                pipeline_data["status"] = status
                if status == 'Succeeded':
                    state["successful_pipelines"].append(pipeline_data)
                else:
                    state["failed_pipelines"].append(pipeline_data)
                save_state(state)
                break
            else:
                time.sleep(10)  # Wait for 10 seconds before checking again
        except client.exceptions.PipelineExecutionNotFoundException as e:
            logging.error(f"Execution not found for pipeline {pipeline_name} (Execution ID: {execution_id}). Retrying...")
            retry_count -= 1
            time.sleep(5)  # Wait before retrying
        except Exception as e:
            logging.error(f"Error monitoring pipeline {pipeline_name}: {str(e)}")
            with lock:
                failed_pipelines.append(pipeline_name)
            # Update state
            pipeline_data = state["in_progress_pipelines"].pop(pipeline_name)
            pipeline_data["pipeline_name"] = pipeline_name  # Add pipeline name to the data
            pipeline_data["stop_time"] = datetime.utcnow().isoformat()
            pipeline_data["status"] = "Failed"
            state["failed_pipelines"].append(pipeline_data)
            save_state(state)
            break

def main(pipeline_file, max_pipelines):
    """Main function to trigger and monitor pipelines."""
    # Validate max_pipelines
    if max_pipelines < 1 or max_pipelines > 4:
        logging.error("max_pipelines must be between 1 and 4.")
        return

    # Read pipeline names from the file
    pipeline_names = read_pipeline_names(pipeline_file)
    if not pipeline_names:
        logging.error("No pipeline names found in the file.")
        return

    # Load state
    state = load_state()
    triggered_pipelines = state["triggered_pipelines"]
    successful_pipelines.extend(state["successful_pipelines"])
    failed_pipelines.extend(state["failed_pipelines"])
    in_progress_pipelines = state["in_progress_pipelines"]

    # Filter out pipelines that have already been processed
    pipelines_to_trigger = [p for p in pipeline_names if p not in triggered_pipelines]

    threads = []
    active_pipelines = 0

    # Resume monitoring for in-progress pipelines
    for pipeline_name, pipeline_data in in_progress_pipelines.items():
        execution_id = pipeline_data["execution_id"]
        thread = Thread(target=monitor_pipeline, args=(pipeline_name, execution_id, state))
        thread.start()
        threads.append(thread)
        active_pipelines += 1

    # Trigger new pipelines
    for pipeline_name in pipelines_to_trigger:
        while active_pipelines >= max_pipelines:
            time.sleep(5)  # Wait if max_pipelines are already running
            active_pipelines = sum(1 for thread in threads if thread.is_alive())

        execution_id = trigger_pipeline(pipeline_name)
        if execution_id:
            active_pipelines += 1
            # Update state
            state["triggered_pipelines"].append(pipeline_name)
            state["in_progress_pipelines"][pipeline_name] = {
                "execution_id": execution_id,
                "start_time": None,  # Will be set in monitor_pipeline
                "stop_time": None,  # Will be set in monitor_pipeline
                "status": None     # Will be set in monitor_pipeline
            }
            save_state(state)
            thread = Thread(target=monitor_pipeline, args=(pipeline_name, execution_id, state))
            thread.start()
            threads.append(thread)

    # Wait for all threads to complete
    for thread in threads:
        thread.join()

    # Log the results
    logging.info("All pipelines have been processed.")
    logging.info(f"Successful pipelines: {successful_pipelines}")
    logging.info(f"Failed pipelines: {failed_pipelines}")

    # Generate completion reports
    generate_completion_report(state)
    generate_markdown_report(state)

    # Delete the pipeline state file after generating the reports
    if Path(STATE_FILE).exists():
        os.remove(STATE_FILE)
        logging.info(f"Deleted the pipeline state file: {STATE_FILE}")

def generate_completion_report(state):
    """Generate a JSON completion report from the state."""
    report = {
        "successful_pipelines": state["successful_pipelines"],
        "failed_pipelines": state["failed_pipelines"],
        "summary": {
            "total_pipelines": len(state["successful_pipelines"]) + len(state["failed_pipelines"]),
            "successful": len(state["successful_pipelines"]),
            "failed": len(state["failed_pipelines"])
        }
    }
    with open("completion_report.json", 'w') as f:
        json.dump(report, f, indent=2)
    logging.info("JSON completion report generated: completion_report.json")

def generate_markdown_report(state):
    """Generate a Markdown completion report from the state."""
    markdown_content = "# Pipeline Execution Report\n\n"
    markdown_content += "## Summary\n\n"
    markdown_content += f"- **Total Pipelines:** {len(state['successful_pipelines']) + len(state['failed_pipelines'])}\n"
    markdown_content += f"- **Successful Pipelines:** {len(state['successful_pipelines'])}\n"
    markdown_content += f"- **Failed Pipelines:** {len(state['failed_pipelines'])}\n\n"

    markdown_content += "## Pipeline Details\n\n"
    markdown_content += "| Pipeline Name | Execution ID | Start Time | Stop Time | Status |\n"
    markdown_content += "|---------------|--------------|------------|-----------|--------|\n"

    for pipeline in state["successful_pipelines"] + state["failed_pipelines"]:
        markdown_content += f"| {pipeline['pipeline_name']} | {pipeline['execution_id']} | {pipeline['start_time']} | {pipeline['stop_time']} | {pipeline['status']} |\n"

    with open("completion_report.md", 'w') as f:
        f.write(markdown_content)
    logging.info("Markdown completion report generated: completion_report.md")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Trigger and monitor AWS CodePipelines.")
    parser.add_argument('--pipelines', type=str, required=True, help="Path to a file containing a list of pipeline names to trigger.")
    parser.add_argument('--max_pipelines', type=int, default=4, choices=range(1, 5), help="Maximum number of pipelines to trigger simultaneously (1-4). Default is 4.")
    args = parser.parse_args()

    main(args.pipelines, args.max_pipelines)
