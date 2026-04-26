import time

def fetch_changes(last_marker):
    # placeholder for CDC logic
    return []

def main():
    marker = 0
    while True:
        changes = fetch_changes(marker)
        for c in changes:
            print("apply change", c)
        time.sleep(5)

if __name__ == "__main__":
    main()
