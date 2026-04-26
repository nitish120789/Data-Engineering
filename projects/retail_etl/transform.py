import pandas as pd


def transform(df: pd.DataFrame) -> pd.DataFrame:
    df["revenue"] = df["quantity"] * df["price"]
    agg = (
        df.groupby(["order_date", "region"], as_index=False)["revenue"]
        .sum()
        .sort_values(["order_date", "region"])
    )
    return agg


if __name__ == "__main__":
    from ingest import ingest

    df = ingest()
    out = transform(df)
    print(out.head())
