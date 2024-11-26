import os
import re
from pathlib import Path

def count_index_search(directory, output_file):
    # Define regex patterns
    match_cnt = re.compile(r'\bcount\s*=\s*')
    match_cnt_index = re.compile(r'\[count.index\]')
    match_bools0 = re.compile(r'\? 0 : 1$')
    match_bools1 = re.compile(r'\? 1 : 0$')
    match_comments = re.compile(r'^\s*#.*')  # Match comment lines
    match_resource_start = re.compile(r'^\s*resource\s+"[^"]*"\s+"[^"]*"\s*{')  # Start of resource block
    match_resource_end = re.compile(r'^\s*}\s*$')  # End of resource block

    total_count = 0
    last_file = None
    inside_resource = False
    resource_lines = []
    current_file = None

    # Open the results file in write mode
    with open(output_file, "w") as results_file:
        # Walk through the directory
        for root, dirs, files in os.walk(directory, topdown=True):
            for file in files:
                file_path = os.path.join(root, file)
                current_file = file

                try:
                    # Only process .tf and .tf.json files
                    if file.endswith(('.tf', '.tf.json')):
                        with open(file_path, 'r', encoding='utf-8') as f:
                            resource_lines = []
                            inside_resource = False
                            match_found = False  # Flag to track if a match was found in the resource block

                            # Process each line in the file
                            for line_num, line in enumerate(f, start=1):
                                line = line.strip()

                                # Detect the start of a resource block
                                if match_resource_start.match(line):
                                    inside_resource = True
                                    resource_lines = [f"Resource Block Start (Line {line_num}): {line}"]

                                # Collect lines inside the resource block
                                if inside_resource:
                                    resource_lines.append(f"Line {line_num}: {line}")

                                # Detect the end of a resource block
                                if inside_resource and match_resource_end.match(line):
                                    inside_resource = False
                                    resource_lines.append(f"Resource Block End (Line {line_num}): {line}")

                                    # Check if the resource block matches the conditions
                                    for res_line in resource_lines:
                                        # Check for `count` and `count.index` matches, but exclude boolean expressions
                                        if (match_cnt.search(res_line) and not (match_bools0.search(res_line) or match_bools1.search(res_line))) or \
                                           (match_cnt_index.search(res_line) and not match_comments.search(res_line)):
                                            match_found = True
                                            break  # Exit the loop once a match is found

                                    # If a match was found, write the entire resource block
                                    if match_found:
                                        if current_file != last_file:
                                            results_file.write(f'--------------\nFile Path: {file_path}\n--------------\n')
                                            last_file = current_file
                                        results_file.write('\n'.join(resource_lines) + "\n\n")
                                        total_count += 1

                                    # Reset for next resource block
                                    resource_lines = []
                                    match_found = False

                except UnicodeDecodeError:
                    print(f"Skipping binary file: {file_path}")

        # Output total match count
        print(f'Total count: {total_count}')


if __name__ == "__main__":
    directory = Path('terraform/')  # Adjust the directory path as needed
    count_index_search(directory, 'results.txt')
