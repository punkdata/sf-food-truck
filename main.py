from fastapi import FastAPI
from fastapi import FastAPI, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.requests import Request
import requests

app = FastAPI()

# Mount static files for CSS
app.mount("/static", StaticFiles(directory="static"), name="static")

# Setup Jinja2 templates
templates = Jinja2Templates(directory="templates")

# URL to fetch data from
DATA_URL = "https://data.sfgov.org/resource/jjew-r69b.json"

@app.get("/", response_class=HTMLResponse)
async def get_search_page(request: Request):
    # Render the search page with no initial results
    return templates.TemplateResponse(request,"search.html", {"request": request, "results": []})

@app.post("/search", response_class=HTMLResponse)
async def search(request:Request, food_type: str = Form(...)):
    try:
        query_url = f'{DATA_URL}/?$q={food_type.lower()}'
        response = requests.get(query_url)
        response.raise_for_status()  # Check for request errors
        data = response.json()
        item = 0
        type_count = 0
        seen_values = []
        unique_applicants = []
        for i in data:
            #Check arrau for unique values
            
            food_item = str(i.get('optionaltext'))
            applicant = str(i.get('applicant'))
            day_order = str(i.get('dayorder'))
            week_day = str(i.get('dayofweekstr'))
            start =str(i.get('startime'))
            end =str(i.get('endtime'))
            location = str(i.get('location'))
            location_desc = str(i.get('locationdesc'))
            permit = str(i.get('permit'))        
            food_served = food_item
            
            if applicant not in seen_values:
                seen_values.append(applicant)
                unique_applicants.append({'applicant':applicant,'foodserved':food_served,'locations':[{'dayorder':day_order,'weekday':week_day,
                            'permit_number':permit,'location':location+' '+location_desc}]})
            else:
                for a in unique_applicants:
                    a.get('locations').append({'dayorder':day_order,'weekday':week_day,'permit_number':permit,'location':location+' '+location_desc})
        # Sort the 'locations' list within each entry by 'dayorder'
        for ua in unique_applicants:
            ua['locations'] = sorted(ua['locations'], key=lambda x: int(x['dayorder']))
        print(unique_applicants)
        return templates.TemplateResponse(request,"search.html", {'request':request,'results':unique_applicants})
    except requests.RequestException as e:
        return {"error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)