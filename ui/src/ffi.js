export function alert_js(message) {
  alert(message);
}

export function ws_init_js() {
  const socket = new WebSocket("ws://localhost:8000/ws");

  socket.onopen = function (e) {
    // alert("[open] Connection established");
    // alert("Sending to server");
    socket.send("ping");
  };

  socket.onmessage = function (event) {
    // on ping
    if (event.data === "pong") {
      socket.send("ping");
      return;
    }
    // alert(`[message] Data received from server: ${event.data}`);
  };

  socket.onclose = function (event) {
    if (event.wasClean) {
      //   alert(
      //     `[close] Connection closed cleanly, code=${event.code} reason=${event.reason}`
      //   );
    } else {
      // e.g. server process killed or network down
      // event.code is usually 1006 in this case
      //   alert("[close] Connection died");
    }
  };

  socket.onerror = function (error) {
    // alert(`[error]`);
  };

  return socket;
}

export function ws_onopen_js(socket, callback) {
  socket.onopen = callback;
}

export function ws_onmessage_js(socket, callback) {
  socket.onmessage = callback;
}

export function ws_onclose_js(socket, callback) {
  socket.onclose = callback;
}

export function ws_onerror_js(socket, callback) {
  socket.onerror = callback;
}

export function ws_send_js(socket, message) {
  socket.send(message);
}
