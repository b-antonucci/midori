import gleam/erlang/process.{type Subject}
import midori/game_manager_message

pub type BotServerMessage {
  // TODO: RequestBotMove should to be a synchronous message
  RequestBotMove(gameid: String, user_id: String, fen: String)
  SetGameManagerSubject(
    subject: Subject(game_manager_message.GameManagerMessage),
  )
}
