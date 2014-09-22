# Description:
#   A Polling scripts for chatwork tasks.
#
# Configuration:
#   HUBOT_CHATWORK_TOKEN
#   HUBOT_CHATWORK_ROOMS
#   HUBOT_CHATWORK_ID
#   HUBOT_API_RATE

{TextMessage}  = require 'hubot'
HTTPS          = require 'https'
{EventEmitter} = require 'events'

module.exports = (robot) ->
  options =
    # chatwork
    chatwork_token: process.env.HUBOT_CHATWORK_TOKEN
    rooms: process.env.HUBOT_CHATWORK_ROOMS
    hubot_id: process.env.HUBOT_CHATWORK_ID # chatwork hubot account ID
    apiRate: process.env.HUBOT_API_RATE

  unless options.chatwork_token? and options.rooms? and options.hubot_id? and options.apiRate?
    robot.logger.error \
      'Not enough parameters provided. I need a token, rooms, chatwork_hubot_id, API rate'
    process.exit 1

  ch_bot = new ChatworkTaskPolling options, robot
  ch_rooms = options.rooms.split ','

  setInterval =>
    for room_id in ch_rooms
      ch_bot.Room(room_id).Tasks().listen()
  , 1000 / (options.apiRate / (60 * 60))

  ch_bot.on 'task', (room_id, messageId, account, body, sendAt, updatedAt) =>
    user = robot.brain.userForId account.account_id,
      name: account.name
      avatarImageUrl: account.avatar_image_url
      room: room_id
    robot.receive new TextMessage user, body, messageId

class ChatworkTaskPolling extends EventEmitter
  constructor: (options, @robot) ->

    @token    = options.chatwork_token
    @hubot_id = options.hubot_id
    @host     = 'api.chatwork.com'
    @rate     = parseInt options.apiRate, 10
    @lastTask = 0

    unless @rate > 0
      @robot.logger.error 'API rate must be greater then 0'
      process.exit 1

  Room: (id) =>
    baseUrl = "/rooms/#{id}"

    Tasks: =>
      show: (callback) =>
        params = []
        params.push "status=open"
        body = params.join '&'
        @get "#{baseUrl}/tasks", body, callback

      listen: =>
        @Room(id).Tasks().show (err, tasks) =>
          for task in tasks
            if @lastTask < task.task_id and "#{task.account.account_id}" is @hubot_id and Math.round(+new Date()/1000) < task.limit_time
              @emit 'task',
                id,
                task.task_id,
                task.account,
                task.body,
                task.send_time,
                task.update_time
              @lastTask = task.task_id

  get: (path, body, callback) ->
    @request "GET", path, body, callback

  request: (method, path, body, callback) ->
    logger = @robot.logger
    console.log "chatwork #{method} #{path} #{body}"

    headers =
      "Host"           : @host
      "X-ChatWorkToken": @token
      "Content-Type"   : "text/plain"

    options =
      "agent"  : false
      "host"   : @host
      "port"   : 443
      "path"   : "/v1#{path}"
      "method" : method
      "headers": headers

    options.headers["Content-Length"] = body.length

    if body.length > 0
      options.path += "?#{body}"

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
              logger.error "Chatwork HTTPS status code: #{response.statusCode}"
              logger.error "Chatwork HTTPS response data: #{data}"

        if callback
          json = try JSON.parse data catch e then data or {}
          callback null, json

      response.on "error", (err) ->
        logger.error "Chatwork HTTPS response error: #{err}"
        callback err, {}

    request.end body

    request.on "error", (err) ->
      logger.error "Chatwork request error: #{err}"
