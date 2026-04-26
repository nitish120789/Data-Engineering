import requests
import json

API_URL = "https://jsonplaceholder.typicode.com/posts"

def fetch_data():
    response = requests.get(API_URL)
    response.raise_for_status()
    return response.json()

if __name__ == "__main__":
    data = fetch_data()
    with open("raw_data.json", "w") as f:
        json.dump(data, f, indent=2)
