import boto3
import csv

def list_organizations():
    client = boto3.client('organizations')
    
    # Open a CSV file for writing
    with open('aws_organizations.csv', mode='w', newline='') as csv_file:
        fieldnames = ['Type', 'Name', 'ID', 'Parent ID', 'Email']
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        
        # List roots (usually there's only one root)
        roots = client.list_roots()['Roots']
        
        for root in roots:
            root_id = root['Id']
            writer.writerow({
                'Type': 'Root',
                'Name': root['Name'],
                'ID': root_id,
                'Parent ID': '',
                'Email': ''
            })
            
            # List OUs under the root
            list_organizational_units(client, root_id, root_id, writer)
            
            # List accounts directly under the root
            list_accounts_for_parent(client, root_id, root_id, writer)

def list_organizational_units(client, parent_id, root_id, writer):
    paginator = client.get_paginator('list_organizational_units_for_parent')
    for page in paginator.paginate(ParentId=parent_id):
        for ou in page['OrganizationalUnits']:
            ou_id = ou['Id']
            writer.writerow({
                'Type': 'Organizational Unit',
                'Name': ou['Name'],
                'ID': ou_id,
                'Parent ID': parent_id,
                'Email': ''
            })
            
            # Recursively list OUs under this OU
            list_organizational_units(client, ou_id, root_id, writer)
            
            # List accounts under this OU
            list_accounts_for_parent(client, ou_id, root_id, writer)

def list_accounts_for_parent(client, parent_id, root_id, writer):
    paginator = client.get_paginator('list_accounts_for_parent')
    for page in paginator.paginate(ParentId=parent_id):
        for account in page['Accounts']:
            writer.writerow({
                'Type': 'Account',
                'Name': account['Name'],
                'ID': account['Id'],
                'Parent ID': parent_id,
                'Email': account['Email']
            })

if __name__ == "__main__":
    list_organizations()
    print("AWS Organizations data has been written to 'aws_organizations.csv'.")
