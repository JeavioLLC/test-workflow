import pytest
from flask.testing import FlaskClient

from app import main
from app.main import _validate_item_name, create_app


@pytest.fixture
def client() -> FlaskClient:
    main._ITEMS.clear()
    app = create_app()
    app.config.update(TESTING=True)
    with app.test_client() as test_client:
        yield test_client


def test_health_returns_ok(client: FlaskClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_index_returns_welcome_message(client: FlaskClient) -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.get_json() == {"message": "Hii from the sample CI/CD application"}


def test_list_items_returns_empty_list_initially(client: FlaskClient) -> None:
    response = client.get("/items")

    assert response.status_code == 200
    assert response.get_json() == {"items": []}


def test_create_item_returns_created_item(client: FlaskClient) -> None:
    response = client.post("/items", json={"name": "widget"})

    assert response.status_code == 201
    assert response.get_json() == {"id": 1, "name": "widget"}


def test_create_item_appends_to_list(client: FlaskClient) -> None:
    client.post("/items", json={"name": "first"})
    client.post("/items", json={"name": "second"})

    response = client.get("/items")

    assert response.status_code == 200
    items = response.get_json()["items"]
    assert [item["name"] for item in items] == ["first", "second"]
    assert [item["id"] for item in items] == [1, 2]


def test_create_item_rejects_missing_name(client: FlaskClient) -> None:
    response = client.post("/items", json={})

    assert response.status_code == 400
    assert response.get_json() == {"error": "invalid item name"}


def test_create_item_rejects_empty_body(client: FlaskClient) -> None:
    response = client.post("/items")

    assert response.status_code == 400
    assert response.get_json() == {"error": "invalid item name"}


def test_create_item_rejects_name_over_100_chars(client: FlaskClient) -> None:
    response = client.post("/items", json={"name": "a" * 101})

    assert response.status_code == 400
    assert response.get_json() == {"error": "invalid item name"}


def test_validate_item_name_accepts_valid_name() -> None:
    assert _validate_item_name("widget") is True


def test_validate_item_name_rejects_empty_name() -> None:
    assert _validate_item_name("") is False


def test_validate_item_name_accepts_name_at_max_length() -> None:
    assert _validate_item_name("a" * 100) is True


def test_validate_item_name_rejects_name_over_max_length() -> None:
    assert _validate_item_name("a" * 101) is False
