$ ->
  #==============================================================================
  # Models
  class FacilityModel extends Backbone.Model

  class FacilityCollection extends Backbone.Collection
    model: FacilityModel
    localStorage: new Store "facilities"

    comparator: (facility) ->
      -1 * facility.get "tons"
    
    getFacilities: (callback) =>     
      console.log 'Getting facilities'
      $.ajax {
        # relative url unless running inside phonegap
        url: if device? then "http://longink.ampdat.com/facilities" else "/facilities?lat=37.93767&lon=-122.39617&dist=5"
        dataType: "json"
        error: (xhr, errMsg, err) ->
          console.log "Error getting facilities" + errMsg
        success: (data) =>
          console.log 'Received nearby facilities'
          console.log data
          for item in data
            if not facilities.detect ((facility) -> facility.get("_id") is item._id)
              console.log 'New facility: ' + item.name
              facilities.create item
          callback()
      }  

  # facilities = new FacilityCollection
  # facilities.fetch()
  # facilities.each (facility) ->
  #   console.log facility

  #==============================================================================
  # Views
  class MapPage extends Backbone.View
    gmap: null
    markers: []


    events : {
      "click a.route-selector" : "handleSelectRoute"
    }

    createMap: ->
      if @gmap is null
        console.log "Creating map"
        latlng = new google.maps.LatLng(37.442138, -122.143196)
        @gmap = new google.maps.Map(document.getElementById("map-canvas"), {zoom: 8, center: latlng, mapTypeId: google.maps.MapTypeId.ROADMAP})
        @directionsService = new google.maps.DirectionsService()
        @directionsDisplay = new google.maps.DirectionsRenderer()
        @directionsDisplay.setMap(@gmap)


    getRoutesAndFacilities: (from, to) ->
      params = { "origin": from, "destination": to, "travelMode": google.maps.DirectionsTravelMode.DRIVING, provideRouteAlternatives: true }
      @directionsService.route params, (response, status) =>
        if status is google.maps.DirectionsStatus.OK
          console.log "Found #{response.routes.length} routes"
          @routeResponse = response
          @directionsDisplay.setDirections(response)
          console.log "Sending routes to server"
          $.ajax '/routes2facilities',
            type: 'POST'
            data: JSON.stringify response.routes
            dataType: 'html'
            error: (jqXHR, textStatus, errorThrown) =>
              console.log "Error sending route to server #{textStatus}"
            success: (result) =>
              @facilityLists = JSON.parse result
              console.log "Received #{@facilityLists.length} lists of facilities"
              $.mobile.pageLoading true
              this.displayRoute(0)
        else
          console.log "Problems routing: #{status}"
  
    displayRoute: (routeNum) ->
      @directionsDisplay.setRouteIndex(routeNum)
      console.log "Found #{@facilityLists[routeNum].length} facilities associated with route #{routeNum}"
      for marker in @markers
        marker.setMap(null)
      for facility in @facilityLists[routeNum]
        do (facility) =>
          marker = new google.maps.Marker {
            position: new google.maps.LatLng(facility.loc[0], facility.loc[1])
            map: @gmap
            title: facility.name
            facility: facility }
          @markers.push(marker)
          infowindow = new google.maps.InfoWindow {content: facility.name, size: new google.maps.Size(50,50)}
          google.maps.event.addListener marker, "click", (e) =>
            # console.log "Clicked on #{this.facility.name}"
            console.log infowindow
            infowindow.setContent("Dude")
            console.log @gmap
            infowindow.open(@gmap)

    handleSelectRoute: (e) ->
      this.displayRoute($(e.currentTarget).data("route-num"))
      
  mapPage = new MapPage {el: $ "#map-page"}

  class FromToPage extends Backbone.View
    events : {
      "click a#get-directions-button" : "createMap"
    }

    createMap: (e) ->
      $.mobile.changePage("#map-page")
      mapPage.createMap()
      $.mobile.loadingMessage = 'Routing...'
      $.mobile.pageLoading false
      mapPage.getRoutesAndFacilities($("#from").val(), $("#to").val())
  
  fromToPage = new FromToPage {el: $('#from-to-page')}
      
  #==============================================================================
  # Controllers  