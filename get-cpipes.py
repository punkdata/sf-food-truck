import boto3
import argparse
from datetime import datetime

def get_codepipeline_names_sorted_by_last_execution(output_file, sort_by_oldest):
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

    # Sort pipelines by the last execution time based on the sort_by_oldest flag
    sorted_pipelines = sorted(pipeline_names, key=lambda x: x[1], reverse=not sort_by_oldest)

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
    # Default file name with timestamp
    default_file_name = f"pipeline-list-{datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"
    # Add --output-file argument with default timestamp-based filename
    parser.add_argument('--output-file', default=default_file_name, help="The name of the file where the pipeline names will be written.")
    # Add --sort-by-oldest argument, defaulting to True
    parser.add_argument('--sort-by-oldest', type=bool, default=True, help="Sort pipelines by the oldest execution time. Defaults to True.")
    
    # Parse arguments
    args = parser.parse_args()

    # Call the function to get pipeline names and write them to the file
    get_codepipeline_names_sorted_by_last_execution(args.output_file, args.sort_by_oldest)

if __name__ == "__main__":
    main()
