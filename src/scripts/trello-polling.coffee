# Description:
#   A Polling scripts for trello actions. Polling cycle is 1 minute.
#
# Dependencies:
#   "cron": ""
#
# Configuration:
#   HUBOT_TRELLO_KEY
#   HUBOT_TRELLO_TOKEN
#   HUBOT_TRELLO_BOARDS (board_id)

{CronJob}      = require 'cron'
HTTPS          = require 'https'
{EventEmitter} = require 'events'

module.exports = (robot) ->
  options =
    trello_key:    process.env.HUBOT_TRELLO_KEY
    trello_token:  process.env.HUBOT_TRELLO_TOKEN
    trello_boards: process.env.HUBOT_TRELLO_BOARDS

  unless options.trello_key? and options.trello_token? and options.trello_boards?
    robot.logger.error \
      'Not enough parameters provided. I need a key, token, boards'
    process.exit 1

  trl_bot = new TrelloPolling options, robot

  boards = options.trello_boards.split ','

  # every 10 seconds
  setInterval =>
    for board_id in boards
      trl_bot.Board(board_id).Actions().polling()
  , 1000 / (360 / (60 * 60))

  trl_bot.on 'built', (msg) =>
    robot.send {}, [msg]

class TrelloPolling extends EventEmitter
  constructor: (options, @robot) ->
    @key   = options.trello_key
    @token = options.trello_token
    @host  = 'trello.com'

    @Message =
      addMemberToBoard: (action) =>
        message = "操作: メンバー追加\n"
        message += "#{action.memberCreator.fullName}が#{action.member.fullName}を#{action.data.board.name}に追加しました."
        @Message.build action, message
      addMemberToCard: (action) =>
        message = "操作: カード割振り\n"
        message += "#{action.memberCreator.fullName}が#{action.member.fullName}を#{action.data.card.name}に追加しました."
        @Message.build action, message
      createList: (action) =>
        message = "操作: リスト作成\n"
        message += "#{action.memberCreator.fullName}が#{action.data.list.name}を作成しました."
        @Message.build action, message
      updateList: (action) =>
        detail =
          name: () =>
            message = "操作: リスト名称変更\n"
            message += "#{action.memberCreator.fullName}が#{action.data.old.name}を#{action.data.list.name}に名称変更しました."
            @Message.build action, message
          closed: () =>
            message = "操作: リスト終了\n"
            message += "#{action.memberCreator.fullName}が#{action.data.list.name}を終了しました."
            @Message.build action, message

        detail[Object.keys(action.data.old)[0]]()
      createCard: (action) =>
        message = "操作: カード作成\n"
        message += "#{action.memberCreator.fullName}が#{action.data.list.name}に#{action.data.card.name}を作成しました."
        @Message.build action, message
      updateCard: (action) =>
        detail =
          idList: () =>
            message = "操作: カードのリスト移動\n"
            message += "#{action.memberCreator.fullName}が#{action.data.card.name}を#{action.data.listBefore.name}から#{action.data.listAfter.name}に移動しました."
            @Message.build action, message
          name: () =>
            message = "操作: カード名称設定\n"
            message += "#{action.memberCreator.fullName}が#{action.data.old.name}を#{action.data.card.name}に名称変更しました."
            @Message.build action, message
          due: () =>
            message = "操作: カード期限設定\n"
            message += "#{action.memberCreator.fullName}が#{action.data.card.name}の期限を#{action.data.card.due.split('T')[0]}に設定しました."
            @Message.build action, message
          desc: () =>
            message = "操作: カード説明設定\n"
            message += "#{action.memberCreator.fullName}が#{action.data.card.name}の説明を#{action.data.card.desc}に設定しました."
            @Message.build action, message
          closed: () =>
            message = "操作: カード終了\n"
            message += "#{action.memberCreator.fullName}が#{action.data.card.name}を終了しました."
            @Message.build action, message

        detail[Object.keys(action.data.old)[0]]()
      deleteCard: (action, callback) =>
        message = "操作: カード削除\n"
        message += "#{action.memberCreator.fullName}が#{action.data.card.id}を削除しました."
        @Message.build action, message
      commentCard: (action, callback) =>
        message = "操作: コメント\n"
        message += "#{action.memberCreator.fullName}が#{action.data.card.name}に\n  #{action.data.text}\nとコメントしました."
        @Message.build action, message

      build: (action, message) =>
        premsg = "ボード: #{action.data.board.name}\n"
        premsg += "リスト: #{action.data.list?.name || ''}\n"
        message = premsg + message
        @emit 'built', message

  Board: (board_id) =>
    baseUrl = "/boards/#{board_id}"

    Actions: =>
      fetch: (callback) =>
        @get "#{baseUrl}/actions", "", callback

      polling: =>
        @Board(board_id).Actions().fetch (err, actions) =>
          lastAction = @robot.brain.get board_id
          if lastAction == null
            @robot.brain.set board_id, actions[0].date
            @robot.brain.save()

          for action in actions.reverse()
            lastAction = @robot.brain.get board_id
            if lastAction < action.date
              @Message[action.type] action
              lastAction = action.date

            @robot.brain.set board_id, lastAction
            @robot.brain.save()

  get: (path, body, callback) ->
    @request "GET", path, body, callback

  request: (method, path, body, callback) ->
    logger = @robot.logger
    # console.log "trello #{method} #{path} #{body}"

    headers =
      "Host" : @host

    options =
      "agent"  : false
      "host"   : @host
      "port"   : 443
      "path"   : "/1#{path}?key=#{@key}&token=#{@token}&limit=5"
      "method" : method
      "headers": headers

    request = HTTPS.request options, (response) ->
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", ->
        if response.statusCode >= 400
          switch response.statusCode
            when 401
              throw new Error "Invalid access token provided"
            else
              logger.error "Trello HTTPS status code: #{response.statusCode}"
              logger.error "Trello HTTPS response data: #{data}"

        if callback
          json = try JSON.parse data catch e then data or {}
          callback null, json

      response.on "error", (err) ->
        logger.error "Trello HTTPS response error: #{err}"
        callback err, {}

    request.end body

    request.on "error", (err) ->
      logger.error "Trello request error: #{err}"
