"""Print one page of VPSes using VPSADMIN_URL and VPSADMIN_TOKEN."""

import os

from haveapi_client import Client, TokenAuth


def main() -> None:
    url = os.environ["VPSADMIN_URL"]
    token = os.environ["VPSADMIN_TOKEN"]

    with Client(url, auth=TokenAuth(token)) as api:
        result = api.vps.list.call(params={"limit": 100}, meta={"count": True})
        for vps in result.data:
            print(vps.id, vps.hostname)

        if "total_count" in result.meta:
            print("Total:", result.meta["total_count"])


if __name__ == "__main__":
    main()
