async = require 'async'
mongoose = require 'mongoose'
Handler = require '../commons/Handler'
AnalyticsLogEvent = require '../models/AnalyticsLogEvent'
Clan = require './../models/Clan'
EarnedAchievement = require '../models/EarnedAchievement'
EarnedAchievementHandler = require './earned_achievement_handler'
LevelSession = require '../models/LevelSession'
LevelSessionHandler = require './level_session_handler'
User = require '../models/User'
UserHandler = require './user_handler'

memberLimit = 200

ClanHandler = class ClanHandler extends Handler
  modelClass: Clan
  jsonSchema: require '../../app/schemas/models/clan.schema'
  allowedMethods: ['GET', 'POST', 'PUT', 'DELETE']

  hasAccess: (req) ->
    return true if req.method is 'GET'
    return false if req.method is 'POST' and req.body?.type is 'private' and not req.user?.isPremium()
    req.method in @allowedMethods or req.user?.isAdmin()

  hasAccessToDocument: (req, document, method=null) ->
    return false unless document?
    return true if req.user?.isAdmin()
    return true if (method or req.method).toLowerCase() is 'get'
    return true if document.get('ownerID')?.equals req.user?._id
    false

  makeNewInstance: (req) ->
    instance = super(req)
    instance.set 'ownerID', req.user._id
    instance.set 'members', [req.user._id]
    instance.set 'dashboardType', 'premium' if req.body?.type is 'private'
    instance


  getByRelationship: (req, res, args...) ->
    return @removeMember(req, res, args[0], args[2]) if args.length is 3 and args[1] is 'remove'
    super(arguments...)

  removeMember: (req, res, clanID, memberID) ->
    return @sendForbiddenError(res) unless req.user? and not req.user.isAnonymous()
    try
      clanID = mongoose.Types.ObjectId(clanID)
      memberID = mongoose.Types.ObjectId(memberID)
    catch err
      return @sendNotFoundError(res, err)
    Clan.findById clanID, (err, clan) =>
      return @sendDatabaseError(res, err) if err
      return @sendNotFoundError(res) unless clan
      return @sendForbiddenError res unless @hasAccessToDocument(req, clan)
      return @sendForbiddenError(res) if clan.get('ownerID').equals memberID
      Clan.update {_id: clanID}, {$pull: {members: memberID}}, (err) =>
        return @sendDatabaseError(res, err) if err
        User.update {_id: memberID}, {$pull: {clans: clanID}}, (err) =>
          return @sendDatabaseError(res, err) if err
          @sendSuccess(res)
          AnalyticsLogEvent.logEvent req.user, 'Clan member removed', clanID: clanID, type: clan.get('type'), memberID: memberID

module.exports = new ClanHandler()
