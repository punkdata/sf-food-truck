import unittest
from unittest.mock import patch, MagicMock
from datetime import datetime
import json
import logging
import os
import sys

# Add the current directory to the Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the script functions
from trigger_pipelines import (
    load_state,
    save_state,
    read_pipeline_names,
    trigger_pipeline,
    monitor_pipeline,
    main,
    generate_completion_report,
    generate_markdown_report,
)

class TestPipelineScript(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        """Set up test environment."""
        # Create a temporary file for pipeline names
        cls.pipeline_file = "test_pipelines.txt"
        with open(cls.pipeline_file, "w") as f:
            for i in range(1, 76):  # 75 pipelines
                f.write(f"pipeline{i}\n")

        # Set up logging to capture logs
        cls.log_filename = f"test_pipeline_execution_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(cls.log_filename),
                logging.StreamHandler()
            ]
        )

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment."""
        # Remove the temporary pipeline file
        if os.path.exists(cls.pipeline_file):
            os.remove(cls.pipeline_file)

        # Remove the log file
        if os.path.exists(cls.log_filename):
            os.remove(cls.log_filename)

        # Remove the state file if it exists
        if os.path.exists("pipeline_state.json"):
            os.remove("pipeline_state.json")

        # Remove the completion report files if they exist
        if os.path.exists("completion_report.json"):
            os.remove("completion_report.json")
        if os.path.exists("completion_report.md"):
            os.remove("completion_report.md")

    def test_load_state(self):
        """Test loading state from a file."""
        # Create a sample state file
        sample_state = {
            "triggered_pipelines": ["pipeline1"],
            "successful_pipelines": [
                {
                    "pipeline_name": "pipeline1",
                    "execution_id": "execution-id-1",
                    "start_time": "2023-10-01T12:00:00.000000",
                    "stop_time": "2023-10-01T12:05:00.000000",
                    "status": "Succeeded"
                }
            ],
            "failed_pipelines": [],
            "in_progress_pipelines": {}
        }
        with open("pipeline_state.json", "w") as f:
            json.dump(sample_state, f)

        # Test loading the state
        state = load_state()
        self.assertEqual(state, sample_state)

    def test_save_state(self):
        """Test saving state to a file."""
        sample_state = {
            "triggered_pipelines": ["pipeline1"],
            "successful_pipelines": [
                {
                    "pipeline_name": "pipeline1",
                    "execution_id": "execution-id-1",
                    "start_time": "2023-10-01T12:00:00.000000",
                    "stop_time": "2023-10-01T12:05:00.000000",
                    "status": "Succeeded"
                }
            ],
            "failed_pipelines": [],
            "in_progress_pipelines": {}
        }
        save_state(sample_state)

        # Verify the state file was created and contains the correct data
        with open("pipeline_state.json", "r") as f:
            saved_state = json.load(f)
        self.assertEqual(saved_state, sample_state)

    def test_read_pipeline_names(self):
        """Test reading pipeline names from a file."""
        pipelines = read_pipeline_names(self.pipeline_file)
        self.assertEqual(len(pipelines), 75)
        self.assertEqual(pipelines[0], "pipeline1")
        self.assertEqual(pipelines[-1], "pipeline75")

    @patch("trigger_pipelines.client")
    def test_trigger_pipeline(self, mock_client):
        """Test triggering a pipeline."""
        # Mock the boto3 client response
        mock_client.start_pipeline_execution.return_value = {
            "pipelineExecutionId": "execution-id-1"
        }

        # Test triggering a pipeline
        execution_id = trigger_pipeline("pipeline1")
        self.assertEqual(execution_id, "execution-id-1")
        mock_client.start_pipeline_execution.assert_called_once_with(name="pipeline1")

    @patch("trigger_pipelines.client")
    def test_monitor_pipeline(self, mock_client):
        """Test monitoring a pipeline."""
        # Mock the boto3 client response
        mock_client.get_pipeline_execution.side_effect = [
            {"pipelineExecution": {"status": "InProgress"}},
            {"pipelineExecution": {"status": "Succeeded"}}
        ]

        # Test monitoring a pipeline
        state = {
            "triggered_pipelines": [],
            "successful_pipelines": [],
            "failed_pipelines": [],
            "in_progress_pipelines": {
                "pipeline1": {
                    "execution_id": "execution-id-1",
                    "start_time": None,
                    "stop_time": None,
                    "status": None
                }
            }
        }
        monitor_pipeline("pipeline1", "execution-id-1", state)

        # Verify the pipeline was marked as successful
        self.assertEqual(len(state["successful_pipelines"]), 1)
        self.assertEqual(state["successful_pipelines"][0]["pipeline_name"], "pipeline1")
        self.assertEqual(state["successful_pipelines"][0]["status"], "Succeeded")

    @patch("trigger_pipelines.client")
    def test_main_with_max_pipelines(self, mock_client):
        """Test the main function with different max_pipelines values."""
        # Mock the boto3 client responses
        mock_client.start_pipeline_execution.side_effect = [
            {"pipelineExecutionId": f"execution-id-{i}"} for i in range(1, 76)
        ]
        mock_client.get_pipeline_execution.side_effect = [
            {"pipelineExecution": {"status": "Succeeded"}} if i % 2 == 0 else {"pipelineExecution": {"status": "Failed"}}
            for i in range(1, 76)
        ]

        # Test with max_pipelines = 1
        main(self.pipeline_file, max_pipelines=1)
        with open("pipeline_state.json", "r") as f:
            state = json.load(f)
        self.assertEqual(len(state["triggered_pipelines"]), 75)
        self.assertGreater(len(state["successful_pipelines"]), 0)
        self.assertGreater(len(state["failed_pipelines"]), 0)

        # Test with max_pipelines = 2
        main(self.pipeline_file, max_pipelines=2)
        with open("pipeline_state.json", "r") as f:
            state = json.load(f)
        self.assertEqual(len(state["triggered_pipelines"]), 75)
        self.assertGreater(len(state["successful_pipelines"]), 0)
        self.assertGreater(len(state["failed_pipelines"]), 0)

        # Test with max_pipelines = 4
        main(self.pipeline_file, max_pipelines=4)
        with open("pipeline_state.json", "r") as f:
            state = json.load(f)
        self.assertEqual(len(state["triggered_pipelines"]), 75)
        self.assertGreater(len(state["successful_pipelines"]), 0)
        self.assertGreater(len(state["failed_pipelines"]), 0)

    def test_generate_completion_report(self):
        """Test generating a JSON completion report."""
        sample_state = {
            "successful_pipelines": [
                {
                    "pipeline_name": "pipeline1",
                    "execution_id": "execution-id-1",
                    "start_time": "2023-10-01T12:00:00.000000",
                    "stop_time": "2023-10-01T12:05:00.000000",
                    "status": "Succeeded"
                }
            ],
            "failed_pipelines": [
                {
                    "pipeline_name": "pipeline2",
                    "execution_id": "execution-id-2",
                    "start_time": "2023-10-01T12:10:00.000000",
                    "stop_time": "2023-10-01T12:15:00.000000",
                    "status": "Failed"
                }
            ]
        }
        generate_completion_report(sample_state)

        # Verify the report was generated
        with open("completion_report.json", "r") as f:
            report = json.load(f)
        self.assertEqual(report["successful_pipelines"], sample_state["successful_pipelines"])
        self.assertEqual(report["failed_pipelines"], sample_state["failed_pipelines"])

    def test_generate_markdown_report(self):
        """Test generating a Markdown completion report."""
        sample_state = {
            "successful_pipelines": [
                {
                    "pipeline_name": "pipeline1",
                    "execution_id": "execution-id-1",
                    "start_time": "2023-10-01T12:00:00.000000",
                    "stop_time": "2023-10-01T12:05:00.000000",
                    "status": "Succeeded"
                }
            ],
            "failed_pipelines": [
                {
                    "pipeline_name": "pipeline2",
                    "execution_id": "execution-id-2",
                    "start_time": "2023-10-01T12:10:00.000000",
                    "stop_time": "2023-10-01T12:15:00.000000",
                    "status": "Failed"
                }
            ]
        }
        generate_markdown_report(sample_state)

        # Verify the report was generated
        with open("completion_report.md", "r") as f:
            content = f.read()
        self.assertIn("pipeline1", content)
        self.assertIn("pipeline2", content)

if __name__ == "__main__":
    unittest.main()