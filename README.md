# San Francisco Food Trucks

This project enables users to search the [City of San Francisco Mobile Food Facility Permit Open Data API][1] for data such as name of vendor, location, type of food sold and status of permit. 

## Purpose

Leveraging the [SF Mobile Food Facility permit data][1] in an example [Python fastapi][2] application. The current state of the project is a minimal viable product and will evolve progressively.

## Requirements

At the time of this writing, this project performs a number of operations on the related data using using various frameworks and technologies. Below are a list of functional requirements that specify function, purpose and current status

| Status | Action | Details |
| ------ | -------- | ------- |
| Completed | Evaluate data/schema | get familiar with the public api and its data|
| Completed | Model the data | model the data from the api to conform with the app spec|
| Completed | Decide project technologies | chose technologies to implement for this project|
| Completed | Write code | write Python code using fastapi to access the open api and retrieve data|
| Completed | Model service responses | create functions that transform api responses into useable data|
| Completed | Consolidate redundant data | create data models that return one `applicant:` and restructure locations into an embedded list|
| Completed | Create Sort on Day function | the `locations:` list must be sorted descending order by day |
| Completed | Create front-end search UI | create a simple search page that takes input and renders the results using Jinja2.|
| Completed | Unit tests | create application unit tests |
| Completed | Dockerfile | create a docker file to build a docker image for this app |
| Completed | Docker Compose | create a docker compose file to build and start a container |
| Completed | Docker Hub | make images publicly available on Docker Hub
| Completed | Vulnerability Scans | create security scans using Snyk
| Completed | CI/CD Pipeline | define a ci/cd pipeline to build, test, scan and deploy the docker image to docker hub |
| Completed | Documentation | create documentation for this project

## Feature Roadmap

The following is a list of future enhancements if time permits:

- Refine the data model to eliminate data duplicate and streamline result sets
- Integrate with Google search and find the applicants business on Google and generate reference links to the business google profile
- Refine and polish the UI design to make it more pleasing to the eye
- Decompose the monolith into a micro services architecture where a web ui service consumes a separate food truck data api service and demonstrates distributed systems concepts.
- Create Infrastructure as Code (IaC) that:
  - Provisions cloud native resources: VPS, Load Balancers, RBAC/IAMS etc..
  - Integrates with AWS, GCP, Azure etc. and other cloud native providers
  - Provision Kubernetes Clusters to host the app
  - Create Kubernetes Manifests or helm charts
- Create persistence layers to capture and serve data from the application
- Provision and implement observability capabilities at the app level and service levels
- Extend the CI/Cd pipeline to include continuous deployment along with other valuable wokflow segments such as compliance scans, deploy and release execution wit rollback factored

## Dependencies

- [SF Mobile Food Facility Permit Open Data API][1]
- [fastapi][2]
- [python][3]
- [jinja][4]
- [Docker][5]
- [Docker Hub][6]
- [Snyk][7]
- [CircleCI][8]

## Usage: Execute locally

Execute this application locally with the following commands:

```shell
pip install -r requirements.txt
uvicorn main:app
```

## Usage: Execute via Docker Compose

Use these commands to build a docker image and start a new container.

```shell
docker compose up -d --build
```

## Usage: Build and Execute with Docker cli

```shell
# Note: the ariv3ra/ segment of this command should be replaced to reflect your user name
docker buildx build ariv3ra/sf_food_trucks:latest .
```

## Usage: Create a local Doker container

```shell
docker run -d --name sf_food_trucks -p8000:8000 ariv3ra/sf_food_trucks:latest
```

[1]:https://data.sfgov.org/Economy-and-Community/Mobile-Food-Facility-Permit/rqzj-sfat/data
[2]:https://fastapi.tiangolo.com/
[3]:https://www.python.org/
[4]:https://jinja.palletsprojects.com/
[5]:https://docker.com/
[6]:https://hub.docker.com/
[7]:https://snyk.io/
[8]:https://circleci.com
