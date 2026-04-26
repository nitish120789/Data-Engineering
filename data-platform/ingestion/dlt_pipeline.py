import dlt

@dlt.resource
def sample_data():
    yield {"id": 1, "value": "test"}

pipeline = dlt.pipeline(pipeline_name="example")
pipeline.run(sample_data())
