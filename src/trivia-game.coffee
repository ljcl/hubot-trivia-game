# Description:
#   Play trivia! Doesn't include questions. Questions should be in the following JSON format:
#   {
#       "answer": "Pizza",
#       "category": "FOOD",
#       "question": "Crust, sauce, and toppings!",
#       "value": "$400"
#   },
#
# Dependencies:
#   cheerio - for questions with hyperlinks
#
# Configuration:
#   None
#
# Commands:
#   #trivia - ask a question
#   #skip - skip the current question
#   #answer <answer> or #a <answer> - provide an answer
#   #hint or #h - take a hint
#   #score <player> - check the score of the player
#   #scores or #score all - check the score of all players
#
# Author:
#   yincrash

Fs = require 'fs'
Path = require 'path'
Cheerio = require 'cheerio'
AnswerChecker = require './answer-checker'

class Game
  @currentQ = null
  @hintLength = null
  @lastAnswer = null

  constructor: (@robot) ->
    buffer = Fs.readFileSync(Path.resolve('./res', 'questions.json'))
    @questions = JSON.parse buffer
    @robot.logger.debug "Initiated trivia game script."

  askQuestion: (resp) ->
    unless @currentQ # set current question
      index = Math.floor(Math.random() * @questions.length)
      @currentQ = @questions[index]
      @hintLength = 1
      @robot.logger.debug "Answer is #{@currentQ.answer}"
      # remove optional portions of answer that are in parentheses
      @currentQ.validAnswer = @currentQ.answer.replace /\(.*\)/, ""
      @currentQ.value = 100 if isNaN(parseInt @currentQ.value)

    $question = Cheerio.load ("<span>" + @currentQ.question + "</span>")
    link = $question('a').attr('href')
    text = $question('span').text()
    resp.send "Answer with #a [your guess]\n" +
              "For _#{@currentQ.value}_ in the category of *#{@currentQ.category}*:\n" +
              ":question: *#{text}*" +
              if link then " #{link}" else ""

  skipQuestion: (resp) ->
    if @currentQ
      resp.send ":grimace: The answer is #{@currentQ.answer}."
      @currentQ = null
      @hintLength = null
      @askQuestion(resp)
    else
      resp.send ":grimace: There is no active question!"

  answerQuestion: (resp, guess) ->
    if @currentQ
      checkGuess = guess.toLowerCase()
      # remove html entities (slack's adapter sends & as &amp; now)
      checkGuess = checkGuess.replace /&.{0,}?;/, ""
      # remove all punctuation and spaces, and see if the answer is in the guess.
      checkGuess = checkGuess.replace /[\\'"\.,-\/#!$%\^&\*;:{}=\-_`~()\s]/g, ""
      checkAnswer = @currentQ.validAnswer.toLowerCase().replace /[\\'"\.,-\/#!$%\^&\*;:{}=\-_`~()\s]/g, ""
      checkAnswer = checkAnswer.replace /^(a(n?)|the)/g, ""
      if AnswerChecker(checkGuess, checkAnswer)
        resp.reply ":tendies: YOU ARE CORRECT! The answer is #{@currentQ.answer}"
        name = resp.envelope.user.name.toLowerCase().trim()
        value = @currentQ.value.replace /[^0-9.-]+/g, ""
        @robot.logger.debug "#{name} answered correctly."
        user = resp.envelope.user
        user.triviaScore = user.triviaScore or 0
        user.triviaScore += parseInt value if !isNaN(parseInt value)
        user.triviaAnswers = user.triviaAnswers or 0
        user.triviaAnswers += 1
        user.triviaCorrect = user.triviaCorrect or 0
        user.triviaCorrect += 1
        resp.reply "Score: $#{user.triviaScore}\n"
        @robot.brain.save()
        @currentQ = null
        @hintLength = null
        @lastAnswer = checkAnswer
        @askQuestion(resp)
      else if @lastAnswer and AnswerChecker(checkGuess, @lastAnswer)
        resp.send "#{guess} is the answer for the previous question, you jabroni."
      else
        user = resp.envelope.user
        user.triviaAnswers = user.triviaAnswers or 0
        user.triviaAnswers += 1
        resp.send "#{guess} is incorrect."
    else
      resp.send "There is no active question!"

  hint: (resp) ->
    if @currentQ
      answer = @currentQ.validAnswer
      @hintLength = 4 if @hintLength < 4 and answer.substr(0,4).toLowerCase() == "the "
      @hintLength = 2 if @hintLength < 2 and answer.substr(0,2).toLowerCase() == "a "
      @hintLength += 1 while [" ", "(", ")", ".", '"', "/"].indexOf(answer.charAt(@hintLength - 1)) != -1
      hiddenPart = answer.substr(@hintLength).replace(/[ ]/g, "   ").replace(/\//g, " / ").replace(/\(/g, " ( ").replace(/\)/g, " ) ").replace(/\./g, " . ").replace(/[^ .)(\/]/g, " _ ")
      hint = answer.substr(0,@hintLength).split('').join(' ') + hiddenPart
      resp.send "`" + hint + "`"
      user = resp.envelope.user
      @hintLength += 1 if @hintLength <= answer.length
      user.triviaHints = user.triviaHints or 0
      user.triviaHints += 1
      @robot.brain.save()
    else
      resp.send "There is no active question!"

  checkScore: (resp, name) ->
    if name == "all"
      scores = ""
      userList = @robot.brain.usersForFuzzyName ""
      userList.sort((a, b) -> (b.triviaScore or 0) - (a.triviaScore or 0))
      for user in userList
        user.triviaScore = user.triviaScore or 0
        user.triviaAnswers = user.triviaAnswers or 0
        user.triviaCorrect = user.triviaCorrect or 0
        correctPercentage = (user.triviaCorrect / user.triviaAnswers * 100).toFixed(2) if user.triviaAnswers > 0
        scores += "#{user.name} - $#{user.triviaScore} (#{user.triviaAnswers} Guesses, #{user.triviaCorrect} Correct, #{correctPercentage}%)\n" if user.triviaScore > 0
      resp.send scores
    else
      user = @robot.brain.userForName name
      unless user
        resp.send "There is no score for #{name}"
      else
        user.triviaScore = user.triviaScore or 0
        user.triviaAnswers = user.triviaAnswers or 0
        user.triviaCorrect = user.triviaCorrect or 0
        user.triviaHints = user.triviaHints or 0
        correctPercentage = (user.triviaCorrect / user.triviaAnswers * 100).toFixed(2) if user.triviaAnswers > 0
        resp.send "#{user.name} - $#{user.triviaScore} (#{user.triviaHints} Hints, #{user.triviaAnswers} Guesses, #{user.triviaCorrect} Correct, #{correctPercentage}%)\n" if user.triviaScore > 0


module.exports = (robot) ->
  game = new Game(robot)
  robot.hear /^#t(rivia)?/, (resp) ->
    game.askQuestion(resp)

  robot.hear /^#skip/, (resp) ->
    game.skipQuestion(resp)

  robot.hear /^#a(nswer)? (.*)/, (resp) ->
    game.answerQuestion(resp, resp.match[2])

  robot.hear /^#score (.*)/i, (resp) ->
    game.checkScore(resp, resp.match[1].toLowerCase().trim())

  robot.hear /^#scores/i, (resp) ->
    game.checkScore(resp, "all")

  robot.hear /^#h(int)?/, (resp) ->
    game.hint(resp)
  
