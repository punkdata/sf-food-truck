import boto3

def list_organizations():
    client = boto3.client('organizations')
    
    # Open a file for writing
    with open('aws_organizations.csv', mode='w') as file:
        # Write the CSV header
        file.write("Type,Name,ID,Parent ID,Email\n")
        
        # List roots (usually there's only one root)
        roots = client.list_roots()['Roots']
        
        for root in roots:
            root_id = root['Id']
            file.write(f"Root,{root['Name']},{root_id},,\n")
            
            # List OUs under the root
            list_organizational_units(client, root_id, root_id, file)
            
            # List accounts directly under the root
            list_accounts_for_parent(client, root_id, root_id, file)

def list_organizational_units(client, parent_id, root_id, file):
    paginator = client.get_paginator('list_organizational_units_for_parent')
    for page in paginator.paginate(ParentId=parent_id):
        for ou in page['OrganizationalUnits']:
            ou_id = ou['Id']
            file.write(f"Organizational Unit,{ou['Name']},{ou_id},{parent_id},\n")
            
            # Recursively list OUs under this OU
            list_organizational_units(client, ou_id, root_id, file)
            
            # List accounts under this OU
            list_accounts_for_parent(client, ou_id, root_id, file)

def list_accounts_for_parent(client, parent_id, root_id, file):
    paginator = client.get_paginator('list_accounts_for_parent')
    for page in paginator.paginate(ParentId=parent_id):
        for account in page['Accounts']:
            file.write(f"Account,{account['Name']},{account['Id']},{parent_id},{account['Email']}\n")

if __name__ == "__main__":
    list_organizations()
    print("AWS Organizations data has been written to 'aws_organizations.csv'.")
