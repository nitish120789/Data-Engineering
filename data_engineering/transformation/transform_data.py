import pandas as pd

def transform():
    df = pd.read_json("raw_data.json")
    df = df.rename(columns={"userId": "user_id"})
    df["title_length"] = df["title"].apply(len)
    df.to_csv("transformed_data.csv", index=False)

if __name__ == "__main__":
    transform()
