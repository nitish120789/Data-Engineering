class Dispatcher:
    def __init__(self):
        pass

    def route(self, event):
        event_type = event.get("type")

        if event_type == "health_threshold_reached":
            return self.handle_threshold(event)

        return "no_action"

    def handle_threshold(self, event):
        # placeholder for orchestration decision
        print("Threshold reached, preparing action pipeline")
        return "prepare_action"

if __name__ == '__main__':
    d = Dispatcher()
    sample_event = {"type": "health_threshold_reached"}
    print(d.route(sample_event))
