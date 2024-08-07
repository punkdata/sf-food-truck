import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_get_search_page():
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "<form" in response.text  # Assuming the form tag is present in the HTML

@pytest.mark.parametrize("food_type, expected_status", [
    ("Burrito", 200),
    ("Tacos", 200),
    ("/", 200),  # Even if the food_type is empty, it should return a valid response
])
def test_search(food_type, expected_status):
    response = client.post("/search", data={"food_type": food_type})
    assert response.status_code == expected_status
    assert "text/html" in response.headers["content-type"]
    assert "<table" in response.text  # Assuming a table is present in the HTML for results
