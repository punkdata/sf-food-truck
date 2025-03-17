import boto3
import argparse
from datetime import datetime

def get_codepipeline_names_sorted_by_last_execution(output_file):
    # Create a CodePipeline client
    client = boto3.client('codepipeline')

    # List all pipelines
    pipelines = client.list_pipelines()

    pipeline_names = []

    # Iterate over pipelines and get the last execution for each pipeline
    for pipeline in pipelines['pipelines']:
        pipeline_name = pipeline['name']

        # Get pipeline history to determine last execution time
        try:
            history = client.list_pipeline_executions(pipelineName=pipeline_name)
            # Sort executions by time and pick the most recent one
            if history['pipelineExecutionSummaries']:
                last_execution = sorted(
                    history['pipelineExecutionSummaries'], 
                    key=lambda x: x['lastUpdateTime'], 
                    reverse=True
                )[0]
                last_execution_time = last_execution['lastUpdateTime']
            else:
                last_execution_time = datetime.min  # If no execution exists

            pipeline_names.append((pipeline_name, last_execution_time))
        except Exception as e:
            print(f"Error retrieving execution history for pipeline {pipeline_name}: {e}")

    # Sort pipelines by the last execution time (oldest to newest)
    sorted_pipelines = sorted(pipeline_names, key=lambda x: x[1])

    # Write the sorted pipeline names to the file
    try:
        with open(output_file, 'w') as f:
            for pipeline, _ in sorted_pipelines:
                f.write(f"{pipeline}\n")
        print(f"Pipeline names have been written to {output_file}")
    except Exception as e:
        print(f"Error writing to file {output_file}: {e}")

def main():
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="List and sort AWS CodePipeline names by last execution time.")
    parser.add_argument('output_file', help="The name of the file where the pipeline names will be written.")
    args = parser.parse_args()

    # Call the function to get pipeline names and write them to the file
    get_codepipeline_names_sorted_by_last_execution(args.output_file)

if __name__ == "__main__":
    main()
