_ = require('underscore')._

http = require "http"
url = require "url"
util = require "util"
fs = require "fs"

static = require "node-static"
mongoose = require "mongoose"

sp = require "./simplifyPath"

# Static http server for files in the client directory
staticServer = new static.Server("../client")

# Open the mongodb database
FacilitySchema = require __dirname + "/facility"
config = require __dirname + "/config"
db = mongoose.connect config.url
FacilityModel = mongoose.model "facility"

# REMIND: Move into import
FacilityModel.collection.ensureIndex [[ "loc", "2d"  ]], () -> {}
FacilityModel.collection.indexInformation (error, doc) ->
  console.log doc

FacilityModel.collection.count (err, count) ->
  console.log "#{count} facilities in the database"


# Start handling requests
httpServer = http.createServer (request, response) ->
  command = url.parse(request.url, true)
  switch command.pathname      
    when "/status"
      response.writeHead 200, {"Content-Type": "text/html"}
      response.write "Triptox server up and running\n"
      response.end()

    when "/routes2facilities"
      body = ""
      request.on "data", (data) ->
        body += data
      request.on "end", ->
        routes = JSON.parse body
        console.log "Found #{routes.length} routes"
        facilityLists = []
        for route in routes
          do (route) ->
            console.log "Looking for facilities near a route"
            # First simplify the route via line straightening to 5 miles tollerance
            simplifiedRoute = sp.GDouglasPeucker(route.overview_path, 1 * 1609.344)
            console.log "Simplified route from #{route.overview_path.length} to #{simplifiedRoute.length} points"
            pointsProcessed = simplifiedRoute.length
            facilityList = []
            for point in simplifiedRoute
              do (point) ->
                radius = 2.5 / 69 # 69 miles per degree roughly
                query = {"loc" : {"\$within" : {"\$center" : [[point.Pa, point.Qa], radius]}}}
                limit = {limit: 50, sort: [["_id", -1]] }
                FacilityModel.collection.find query, limit, (error, cursor) ->
                  cursor.toArray (error, results) ->
                    console.log "Found #{results.length} facilities within #{radius} of #{point.Pa},#{point.Qa}\n"
                    for facility in results
                      facilityList.push(facility) unless _.detect(facilityList, (f) -> facility._id.equals(f._id))
                    pointsProcessed--
                    if pointsProcessed is 0
                      console.log "Found a total of #{facilityList.length} uniq facilities"
                      if facilityLists.push(facilityList) is routes.length
                        response.writeHead 200, {"Content-Type": "application/json"}
                        response.write JSON.stringify(facilityLists)
                        response.end()

    # Given a list of routes defined by a list of points return a list of facilities for each
    # route that are close to that path.
    # REMIND: Currently this just takes the path as a polygon so its a very poor search, need
    # to develop algorithm to expand a path into a corridor
    # when "/routes2facilities"
    #   body = ""
    #   request.on "data", (data) ->
    #     body += data
    #   request.on "end", ->
    #     routes = JSON.parse body
    #     console.log "Found #{routes.length} routes"
    #     facilityLists = []
    #     for route in routes
    #       console.log "Looking for facilities near a route"
    #       query = {"loc" : {"\$within" : {"\$polygon" : route.overview_path}}}
    #       limit = {limit: 20, sort: [["_id", -1]] }
    #       FacilityModel.collection.find query, limit, (error, cursor) =>
    #         cursor.toArray (error, facilities) =>
    #           console.log "Found #{facilities.length} facilities near the route\n"
    #           if facilityLists.push(facilities) is routes.length
    #             response.writeHead 200, {"Content-Type": "application/json"}
    #             response.write JSON.stringify(facilityLists)
    #             response.end()

    # Given a route defined by a list of points return a list of facilities
    # near that route by performing a series of radial searches using points
    # on the path
    when "/route2facilities"
      body = ""
      distance = parseFloat(command.query.dist)
      radius = distance / 112.63
      limit = {limit: 20, sort: [["_id", -1]] }
      request.on "data", (data) ->
        body += data
      request.on "end", ->
        route = JSON.parse body
        console.log "Found route with #{route.length} points"
        facilities = []
        for point in route
          query = {"loc" : {"\$within" : {"\$center" : [[point[0],point[1]], radius]}}}
          FacilityModel.collection.find query, limit, (error, cursor) =>
            cursor.toArray (error, facilities) =>
              console.log "Found #{facilities.length} facilities near #{point}\n"
              if facilities.push(facilities) is routes.length
                response.writeHead 200, {"Content-Type": "application/json"}
                response.write JSON.stringify(facilityLists)
                response.end()
    
    # Given a center and radius find all the facilities within that circle
    when "/loc2facilities"
      console.log command.query
      center = [parseFloat(command.query.lat), parseFloat(command.query.lon)]
      distance = parseFloat(command.query.dist)
      radius = distance / 112.63
      query = {"loc" : {"\$within" : {"\$center" : [center, radius]}}}
      limit = {limit: 100, sort: [["_id", -1]] }
      console.log "Querying: " + center[0].toString() + " : " + center[1].toString() + ", " + distance.toString()
      FacilityModel.collection.find query, limit, (error, cursor) ->
        cursor.toArray (error, results) ->
          console.log "Found #{results.length}\n"
          response.writeHead 200, {"Content-Type": "text/html"}
          response.write JSON.stringify(results)
          response.end()
    
    # Given a rectangle find all the facilities within it
    # bounds2facilities?bounds=34.172684,-118.604794,34.236144,-118.500938
    when "/bounds2facilities"
      console.log command.query
      bounds = command.query.bounds.split(",")
      box = [[parseFloat(bounds[0]), parseFloat(bounds[1])], [parseFloat(bounds[2]), parseFloat(bounds[3])]]
      distance = parseFloat(command.query.dist)
      radius = distance / 112.63
      query = {"loc" : {"\$within" : {"\$box" : box}}}
      limit = {limit: 100, sort: [["_id", -1]] }
      FacilityModel.collection.find query, limit, (error, cursor) ->
        cursor.toArray (error, results) ->
          console.log "Found #{results.length}\n"
          response.writeHead 200, {"Content-Type": "text/html"}
          response.write JSON.stringify(results)
          response.end()

    else 
      request.addListener "end", ->
        console.log("Servicing static request to " + request.url)
        staticServer.serve(request, response)

httpServer.listen(3000)
console.log "Server listening on port 3000"