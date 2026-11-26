import subprocess
import sys


def main(image: str) -> None:
    size = int(
        subprocess.check_output(
            ["docker", "image", "inspect", "--format", "{{.Size}}", image], text=True
        )
    )
    uid = subprocess.check_output(["docker", "run", "--rm", image, "id", "-u"], text=True).strip()
    subprocess.run(
        [
            "docker", "run", "--rm", image, "python", "-c",
            "from importlib.util import find_spec; "
            "assert all(find_spec(x) is None for x in "
            "('osgeo', 'shapely', 'fiona', 'geopandas', 'pyproj'))",
        ],
        check=True,
    )
    print(f"{image} has {size:,} uncompressed bytes across all layers and runs as UID {uid}")
    if size > 100 * 1024 * 1024 or uid != "10001":
        raise SystemExit("Runtime image size or runtime user violates the required limit")


if __name__ == "__main__":
    main(sys.argv[1])
