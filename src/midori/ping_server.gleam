import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import mist.{type WebsocketConnection}

// TODO: Ping server needs to be rewritten as I start to implement timed play. 
// Instead of waiting on the
// client to send a message to the server, the server should periodically
// send a ping message to the client. The client should then respond with
// a pong message. If the client does not respond with a pong message
// within a certain time frame, things need to happen. The ping server
// will also need to calculate latency for the purposes of accurate
// time keeping(adjusting in game clock to compensate for time lost due
// to waiting on message to arrive as server).

pub type PingServerMessage {
  Ping(conn: WebsocketConnection)
}

fn handle_message(
  message: PingServerMessage,
  state: String,
) -> actor.Next(PingServerMessage, String) {
  case message {
    Ping(conn) -> {
      process.sleep(10_000)
      let assert Ok(nil) = mist.send_text_frame(conn, "1")
      nil
    }
  }
  actor.continue(state)
}

pub fn start_ping_server() -> Result(Subject(PingServerMessage), _) {
  let actor = actor.start("Ping Pong", handle_message)
  actor
}
