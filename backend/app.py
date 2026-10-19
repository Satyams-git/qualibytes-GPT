import logging
import os

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
log = logging.getLogger("qualibytes-backend")

# Ollama runs as a separate container on the same Docker network
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
MODEL_NAME = os.getenv("MODEL_NAME", "tinyllama")

# tinyllama has a 2048-token context — only send the most recent turns
MAX_HISTORY = int(os.getenv("MAX_HISTORY", "10"))
MAX_MESSAGE_CHARS = int(os.getenv("MAX_MESSAGE_CHARS", "4000"))
ALLOWED_ROLES = {"user", "assistant"}

SYSTEM_MESSAGE = {
    "role": "system",
    "content": (
        "You are Qualibytes GPT, a helpful and friendly AI assistant. "
        "You give clear, concise answers. Keep responses short and to the point."
    ),
}

# No CORS: the browser calls /api/chat on the same origin through the
# Nginx proxy, so cross-origin access is neither needed nor allowed.


@app.route("/health", methods=["GET"])
def health():
    """Health check — pipeline uses this to verify deploy success."""
    return jsonify({"status": "OK", "app": "Qualibytes GPT Backend", "model": MODEL_NAME})


def _validate(messages):
    """Return a cleaned message list, or an error string."""
    if not isinstance(messages, list) or len(messages) == 0:
        return None, "messages must be a non-empty list"
    cleaned = []
    for m in messages:
        if not isinstance(m, dict):
            return None, "each message must be an object"
        role, content = m.get("role"), m.get("content")
        if role not in ALLOWED_ROLES:
            return None, "message role must be 'user' or 'assistant'"
        if not isinstance(content, str) or not content.strip():
            return None, "message content must be a non-empty string"
        if len(content) > MAX_MESSAGE_CHARS:
            return None, f"message content is longer than {MAX_MESSAGE_CHARS} characters"
        cleaned.append({"role": role, "content": content})
    return cleaned[-MAX_HISTORY:], None


@app.route("/api/chat", methods=["POST"])
def chat():
    """
    Accepts conversation history and returns AI reply.
    Request body: { "messages": [{ "role": "user", "content": "..." }, ...] }
    """
    data = request.get_json(silent=True)
    if not data or "messages" not in data:
        return jsonify({"error": "messages field is required"}), 400

    messages, error = _validate(data["messages"])
    if error:
        return jsonify({"error": error}), 400

    try:
        # Call Ollama /api/chat endpoint (supports multi-turn conversation)
        response = requests.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": MODEL_NAME,
                "messages": [SYSTEM_MESSAGE] + messages,
                "stream": False,
                "options": {
                    "temperature": 0.7,
                    "num_predict": 300,  # Limit response length for t2.small
                },
            },
            timeout=90,  # tinyllama can be slow on small instances
        )
        response.raise_for_status()
        reply = response.json()["message"]["content"].strip()
        return jsonify({"reply": reply})

    except requests.exceptions.ConnectionError:
        return jsonify({"error": "Ollama service is not reachable. Is it running?"}), 503
    except requests.exceptions.Timeout:
        return jsonify({"error": "Ollama timed out. Model may still be loading — try again."}), 504
    except Exception:
        # Log the details server-side; don't leak internals to the browser
        log.exception("Chat request failed")
        return jsonify({"error": "Something went wrong while generating a reply."}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
