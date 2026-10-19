"""API-only compatibility with the real pinned vpsAdmin/Ruby server."""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from vpsadmin_support import (
    assert_continuation_rejected,
    assert_token_rejected,
    load_manifest,
    resolve,
    totp,
    unused_totp,
)

from haveapi_client import (
    AsyncAuthenticationChallenge,
    AsyncClient,
    Authenticated,
    AuthenticationChallenge,
    BasicAuth,
    Client,
)
from haveapi_client.exceptions import (
    ActionError,
    AuthenticationError,
    NotConnectedError,
    StaleDescriptionError,
    ValidationError,
)

pytestmark = [pytest.mark.integration, pytest.mark.anyio]


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def manifest():
    return load_manifest()


@pytest.fixture
async def api(manifest) -> AsyncIterator[Client | AsyncClient]:
    cls = AsyncClient if manifest["mode"] == "async" else Client
    client = cls(manifest["base_url"], timeout=10)
    try:
        yield client
    finally:
        await resolve(
            client.aclose() if isinstance(client, AsyncClient) else client.close()
        )


async def basic(api, manifest, identity="user"):
    user = manifest[identity]
    await resolve(api.set_auth(BasicAuth(user["login"], manifest["password"])))
    return user


async def assert_current(api, expected_id):
    response = await resolve(api.user.current())
    assert response.data["id"] == expected_id
    return response


async def begin(api, manifest, *, password=None):
    return await resolve(
        api.begin_token_login(
            {
                "user": manifest["user"]["login"],
                "password": password or manifest["password"],
                "lifetime": "renewable_manual",
                "interval": 3600,
                "scope": "all",
            }
        )
    )


async def reject_continuation_as_identity(api, manifest):
    # The bridge inspects actual AuthToken persistence separately. A challenge
    # does not install a usable API identity in the public facade.
    with pytest.raises(NotConnectedError):
        _ = api.user
    assert api.generation > 0


async def test_reads(api, manifest):
    await resolve(api.connect())
    public = api.description
    user = await basic(api, manifest)
    await assert_current(api, user["id"])
    ordinary = api.description
    response = await resolve(
        api.vps.list.call(params={"limit": 100}, meta={"count": True})
    )
    ids = {row["id"] for row in response.data}
    assert ids == set(manifest["own_vps_ids"])
    assert response.meta["total_count"] == len(ids)
    assert manifest["other_vps_id"] not in ids
    detail = await resolve(
        api.vps[manifest["own_vps_ids"][0]].show.call(meta={"includes": "os_template"})
    )
    assert detail.data["user"]["id"] == user["id"]
    assert detail.data["os_template"]["id"] == manifest["os_template_id"]
    assert detail.data.meta is not None
    with pytest.raises(ActionError):
        await resolve(api.vps[manifest["other_vps_id"]].show())
    interfaces = await resolve(
        api.network_interface.list(vps=manifest["own_vps_ids"][0])
    )
    assert {row["id"] for row in interfaces.data} == {manifest["own_interface_id"]}
    assert (
        "user"
        not in ordinary.resources["network_interface"].actions["index"].input.parameters
    )
    with pytest.raises(ValidationError):
        await resolve(api.vps.list(limit="invalid-integer"))
    # Source uses ascending id > from_id. Observe bounded pages explicitly;
    # this does not claim snapshot consistency for changing production data.
    cursor = 0
    observed = []
    for _ in range(len(ids) + 1):
        page = await resolve(api.vps.list(limit=1, from_id=cursor))
        if not page.data:
            break
        value = page.data[0]["id"]
        assert value > cursor
        observed.append(value)
        cursor = value
    assert observed == sorted(ids)
    stale = api.vps.list
    await basic(api, manifest, "admin")
    with pytest.raises(StaleDescriptionError):
        await resolve(stale())
    admin_description = api.description
    assert (
        "user"
        in admin_description.resources["network_interface"]
        .actions["index"]
        .input.parameters
    )
    all_rows = await resolve(api.vps.list(limit=100))
    assert {row["id"] for row in all_rows.data} == ids | {manifest["other_vps_id"]}
    nullable = await resolve(api.vps.list(user_namespace_map=None, limit=100))
    assert {row["id"] for row in nullable.data} == ids | {manifest["other_vps_id"]}
    assert set(public.resources) <= set(admin_description.resources)
    assert ordinary.raw != admin_description.raw


async def test_tokens(api, manifest):
    result = await begin(api, manifest)
    assert isinstance(result, Authenticated)
    await assert_current(api, manifest["user"]["id"])
    renewed = await resolve(api.renew_token())
    assert renewed.data["valid_to"]
    authorized = api.description
    await resolve(api.revoke_token())
    await assert_token_rejected(manifest, authorized, result.token)
    await assert_token_rejected(manifest, authorized, manifest["expired_token"])


async def test_totp(api, manifest):
    await assert_continuation_rejected(manifest)
    challenge = await begin(api, manifest)
    assert isinstance(
        challenge, (AuthenticationChallenge, AsyncAuthenticationChallenge)
    )
    assert challenge.next_action == "totp"
    assert "code" in challenge.input and "token" not in challenge.input
    await reject_continuation_as_identity(api, manifest)
    with pytest.raises((AuthenticationError, ActionError)):
        await resolve(challenge.submit({"code": "invalid-code"}))
    result = await resolve(challenge.submit({"code": totp(manifest["totp_secret"])}))
    assert isinstance(result, Authenticated)
    await assert_current(api, manifest["user"]["id"])


async def test_reset(api, manifest):
    await assert_continuation_rejected(manifest)
    challenge = await begin(api, manifest)
    assert isinstance(
        challenge, (AuthenticationChallenge, AsyncAuthenticationChallenge)
    )
    assert challenge.next_action == "reset_password"
    await finish_reset(api, manifest, challenge)


async def test_totp_reset(api, manifest):
    await assert_continuation_rejected(manifest)
    challenge = await begin(api, manifest)
    assert isinstance(
        challenge, (AuthenticationChallenge, AsyncAuthenticationChallenge)
    )
    assert challenge.next_action == "totp"
    await reject_continuation_as_identity(api, manifest)
    code = totp(manifest["totp_secret"])
    manifest["last_totp_code"] = code
    challenge = await resolve(challenge.submit({"code": code}))
    assert isinstance(
        challenge, (AuthenticationChallenge, AsyncAuthenticationChallenge)
    )
    assert challenge.next_action == "reset_password"
    await finish_reset(api, manifest, challenge)


async def finish_reset(api, manifest, challenge):
    await reject_continuation_as_identity(api, manifest)
    with pytest.raises((AuthenticationError, ActionError, ValidationError)):
        await resolve(
            challenge.submit(
                {"new_password1": "too-short", "new_password2": "different"}
            )
        )
    with pytest.raises((AuthenticationError, ActionError, ValidationError)):
        await resolve(challenge.submit({"new_password1": "x", "new_password2": "x"}))
    result = await resolve(
        challenge.submit(
            {
                "new_password1": manifest["new_password"],
                "new_password2": manifest["new_password"],
            }
        )
    )
    assert isinstance(result, Authenticated)
    await assert_current(api, manifest["user"]["id"])
    await resolve(api.logout())
    with pytest.raises((AuthenticationError, ActionError)):
        await begin(api, manifest)
    result = await begin(api, manifest, password=manifest["new_password"])
    if isinstance(result, (AuthenticationChallenge, AsyncAuthenticationChallenge)):
        assert result.next_action == "totp"
        result = await resolve(result.submit({"code": await unused_totp(manifest)}))
    assert isinstance(result, Authenticated)
    await assert_current(api, manifest["user"]["id"])
