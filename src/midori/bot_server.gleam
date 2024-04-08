import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/string
import glexec.{type Pids, Execve, run_async}

pub type BotServerMessage {
  GetBotMove(reply_with: Subject(String), fen: String)
}

pub type BotServerState {
  BotServerState
}

fn handle_message(
  message: BotServerMessage,
  state: BotServerState,
) -> actor.Next(BotServerMessage, BotServerState) {
  case message {
    GetBotMove(client, fen) -> {
      let assert fairy_stockfish_command =
        Execve(["./fairy-stockfish-largeboard_x86-64-modern"])
      let options =
        glexec.new()
        |> glexec.with_stdin(glexec.StdinPipe)
        |> glexec.with_stdout(glexec.StdoutCapture)
      let assert Ok(glexec.Pids(_pid, ospid)) =
        run_async(options, fairy_stockfish_command)
      let assert Ok(_) = glexec.send(ospid, "position fen " <> fen <> "\n")
      let assert Ok(_) = glexec.send(ospid, "go movetime 1\n")
      let assert Ok(output) = obtain_best_move(fen, 50)
      let _ = glexec.stop(ospid)
      process.send(client, output)
    }
  }
  actor.continue(state)
}

pub fn obtain_best_move(fen: String, depth: Int) -> Result(String, _) {
  let assert Ok(glexec.ObtainStdout(_, stdout_string)) = glexec.obtain(500)
  case string.is_empty(stdout_string) {
    True -> Error("No move found")
    False ->
      case string.contains(stdout_string, "bestmove") {
        True -> {
          case string.split(stdout_string, "bestmove") {
            [_, move] -> {
              let assert Ok(move) = list.at(string.split(move, " "), 1)
              Ok(move)
            }
            _ -> Error("Could no split bestmove from output")
          }
        }
        False ->
          case depth {
            0 -> Error("depth exceeded")
            _ -> obtain_best_move(fen, depth - 1)
          }
      }
  }
}

pub fn start_bot_server() -> Result(Subject(BotServerMessage), _) {
  let actor = actor.start(BotServerState, handle_message)
  actor
}
