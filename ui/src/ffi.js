export function alert_js(message) {
  alert(message);
}

export function alert_js_object_data(message) {
  alert(message.data);
}

export function get_data_as_string_js(some_object) {
  return some_object.data;
}

export function get_data_field_js(some_object, field) {
  let data_object = JSON.parse(some_object.data);
  return data_object[field];
}

export function get_data_field_array_js(some_object, field) {
  let data_object = JSON.parse(some_object.data);
  return data_object[field];
}

export function get_data_field_object_js(some_object, field) {
  let data_object = JSON.parse(some_object.data);
  return JSON.stringify(data_object[field]);
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

export function ws_send_move_js(socket, message) {
  message = Object.assign({ type: "move" }, message);
  socket.send(JSON.stringify(message));
}

export function console_log_js(message) {
  console.log(message);
}
