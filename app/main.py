from flask import Flask, jsonify, request
from flask.wrappers import Response

_ITEMS: list[dict] = []


def _validate_item_name(name: str) -> bool:
    return bool(name) and len(name) <= 100


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/health")
    def health() -> Response:
        return jsonify(status="ok")

    @app.get("/")
    def index() -> Response:
        return jsonify(message="Hii from the sample CI/CD application")

    @app.get("/items")
    def list_items() -> Response:
        return jsonify(items=_ITEMS)

    @app.post("/items")
    def create_item() -> tuple[Response, int]:
        payload = request.get_json(silent=True) or {}
        name = payload.get("name", "")

        if not _validate_item_name(name):
            return jsonify(error="invalid item name"), 400

        item = {"id": len(_ITEMS) + 1, "name": name}
        _ITEMS.append(item)
        return jsonify(item), 201

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
