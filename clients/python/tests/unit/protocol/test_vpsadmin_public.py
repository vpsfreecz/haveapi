"""Parse a captured subset of vpsAdmin's unauthenticated public description."""

import json
from pathlib import Path

from haveapi_client._protocol import parse_description

FIXTURE = Path(__file__).parents[2] / "fixtures" / "vpsadmin_public.json"


def test_captured_public_description() -> None:
    envelope = json.loads(FIXTURE.read_text())
    description = parse_description(envelope)

    assert description.protocol_version == "2.0"
    assert description.api_version is None
    assert description.meta_namespace == "_meta"
    assert set(description.resources) == {"vps", "network_interface"}
    assert (
        description.authentication.keys()
        == envelope["response"]["authentication"].keys()
    )

    for name, collection, identifier in (
        ("vps", "vpses", "vps_id"),
        ("network_interface", "network_interfaces", "network_interface_id"),
    ):
        resource = description.resources[name]
        assert resource.resource_path == (name,)
        assert set(resource.actions) == {"index", "show"}
        assert not resource.resources

        index = resource.actions["index"]
        assert index.method == "GET"
        assert index.path == f"/v7.0/{collection}"
        assert index.aliases == ("list",)
        assert index.output is not None
        assert index.output.layout == "object_list"
        assert index.output.namespace == collection

        show = resource.actions["show"]
        assert show.method == "GET"
        assert show.path == f"/v7.0/{collection}/{{{identifier}}}"
        assert show.path_parameters == (identifier,)
        assert show.aliases == ("find",)
        assert show.output is not None
        assert show.output.layout == "object"
        assert show.output.namespace == name
