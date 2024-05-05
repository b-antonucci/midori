import gleam/erlang/process.{type Subject}
import midori/game_manager_message

pub type BotServerMessage {
  NextMove
  // TODO: RequestBotMove should to be a synchronous message
  RequestBotMove(gameid: String, user_id: String, fen: String)
  SendBotMove(move: String)
  SetOsPid(pid: Int)
  SetGameManagerSubject(
    subject: Subject(game_manager_message.GameManagerMessage),
  )
  SetSelfSubject(subject: Subject(BotServerMessage))
}
