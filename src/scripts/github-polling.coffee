# Description:
#   A Polling scripts for github repositories. Polling cycle is 1 minute.
#
# Configuration:
#   HUBOT_GITHUB_TOKEN
#   HUBOT_GITHUB_OWNER
#   HUBOT_GITHUB_REPOS (Optional)

{CronJob}      = require 'cron'
HTTPS          = require 'https'
{EventEmitter} = require 'events'

module.exports = (robot) ->
  options =
    github_token: process.env.HUBOT_GITHUB_TOKEN
    github_owner: process.env.HUBOT_GITHUB_OWNER
    github_repos: process.env.HUBOT_GITHUB_REPOS

  unless options.github_token? and options.github_owner?
    robot.logger.error \
      'Not enough parameters provided. I need a token, repos, owner'
    process.exit 1

  gh_bot = new GithubPolling options, robot

  gh_repos = []
  if options.github_repos
    repos = options.github_repos.split ','
    for repo in repos
      gh_repos.push { "name": repo }

  cronjob = new CronJob '*/1 * * * *', () =>
    if gh_repos.length > 0
      gh_bot.emit 'repo_set', gh_repos
    else
      gh_bot.Users().repos()

  cronjob.start()

  gh_bot.on 'commit', (msg) =>
    robot.send {}, [msg]

  gh_bot.on 'repo_set', (repos) =>
    for repo in repos
      gh_bot.Repos(repo.name).Commits().polling()

class GithubPolling extends EventEmitter
  constructor: (options, @robot) ->

    @token = options.github_token
    @owner = options.github_owner
    @host  = 'api.github.com'

  Users: =>
    fetch: (callback) =>
      @get "/user/repos?type=owner", "", callback

    repos: () =>
      @Users().fetch (err, repos) =>
        @emit 'repo_set', repos

  Repos: (repo_name) =>
    Commits: =>
      fetch: (callback) =>
        @get "/repos/#{@owner}/#{repo_name}/commits", "", callback

      polling: () =>
        @Repos(repo_name).Commits().fetch (err, commits) =>
          message = {}
          lastCommit = @robot.brain.get repo_name
          if lastCommit == null
            @robot.brain.set repo_name, commits[0].commit.committer.date
            @robot.brain.save()

          for commit in commits.reverse()
            # initialize message component
            message["msg"] = "" if message["msg"] is undefined

            lastCommit = @robot.brain.get repo_name
            if lastCommit < commit.commit.committer.date
              # add commit message
              message["user"] = commit.committer.login
              message["msg"] += "  * #{commit.commit.message}: ( #{commit.html_url} )\n"
              lastCommit = commit.commit.committer.date

            @robot.brain.set repo_name, lastCommit
            @robot.brain.save()

          if message["msg"] != ""
            msg = "#{message["user"]}さんが#{repo_name}にコミットしました.\n" + message["msg"]
            @emit 'commit',
              msg

  get: (path, body, callback) ->
    @request 'GET', path, body, callback

  request: (method, path, body, callback) ->
    logger = @robot.logger
    # console.log "github #{method} #{path} #{body}"

    headers =
      "Host": @host
      "Authorization": "token #{@token}"
      "User-Agent": @owner

    options =
      "agent"  : false
      "host"   : @host
      "port"   : 443
      "path"   : path
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
              logger.error "GitHub HTTPS status code: #{response.statusCode}"
              logger.error "GitHub HTTPS response data: #{data}"

        if callback
          json = try JSON.parse data catch e then data or {}
          callback null, json

      response.on "error", (err) ->
        logger.error "GitHub HTTPS response error: #{err}"
        callback err, {}

    request.end body

    request.on "error", (err) ->
      logger.error "GitHub request error: #{err}"
