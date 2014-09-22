# Description:
#   Post Message to Chatwork
#
# Dependencies:
#   "url": ""
#   "querystring": ""
#
# URLS:
#   POST /hubot/post-to-chat-app?room=<room> with message body

url = require('url')
querystring = require('querystring')

module.exports = (robot) ->

  robot.router.post "/hubot/post-to-chat-app", (req, res) ->
    query = querystring.parse(url.parse(req.url).query)
    res.send 200

    user = {}
    user.room = query.room if query.room

    body = req.body

    robot.send user, [body.body]
