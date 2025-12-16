import os,sys


def main():

    # show paths so we can confirm what's happening
    print("hello from hello_uv")
    print("sys.executable:", sys.executable)
    print("cwd:", os.getcwd())
    print("UV_PROJECT_ENVIRONMENT:", os.environ.get("UV_PROJECT_ENVIRONMENT"))
    print("UV_CACHE_DIR:", os.environ.get("UV_CACHE_DIR"))
    print("PYTHONPATH:", os.environ.get("PYTHONPATH"))


if __name__ == "__main__":
    main()

