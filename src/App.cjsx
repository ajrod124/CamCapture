React = require 'react'
require './App.css'

App = React.createClass
	getInitialState: ->
		streaming: false
		viewing: false
		lastMessage: ''
		connectedPeers: 0

	componentWillMount: ->
		@ws = new WebSocket 'ws://107.170.222.119:3000'
		@setupSocket()
		@pc = null
		@localStream = null

	componentDidMount: -> @video = document.getElementById 'feed'

	setupSocket: ->
		@ws.onopen = () =>
			console.log 'Socket opened'
		@ws.onmessage = (e) =>
			obj = JSON.parse e.data
			switch obj.type
				when 'chatEvent'
					@setState
						lastMessage: obj.message
				when 'exchangeCandidates'
					if (@state.streaming and obj.source is 'viewer') or (@state.viewing and obj.source is 'streamer')
						@addIceCandidate obj.candidate
				when 'exchangeDescription'
					if (@state.streaming and obj.source is 'viewer') or (@state.viewing and obj.source is 'streamer')
						@setRemoteDescription obj.desc
				when 'readyForExchange'
					if @state.streaming then @prepareStream()
				when 'closeComms'
					@end()
				else
					console.error 'Unexpected response from socket server: ', obj
		@ws.onclose = (e) =>
			console.log e

	setupPC: (type) ->
		@pc = new RTCPeerConnection
			'iceServers': [
				'url': 'stun:stun.l.google.com:19302'
			]

		@pc.onicecandidate = (event) =>
			console.log 'onicecandidate'
			if event.candidate
				@ws.send JSON.stringify
					type: 'exchangeCandidates'
					candidate: event.candidate
					source: type

		@pc.oniceconnectionstatechange = (event) =>
			console.log 'oniceconnectionstatechange', event.target.iceConnectionState

		@pc.onsignalingstatechange = (event) =>
			console.log 'onsignalingstatechange', event.target.signalingState

		@pc.onnegotiationneeded = () =>
			console.log 'onnegotiationneeded'

		if type is 'viewer'
			@pc.onaddstream = (event) =>
				@video.srcObject = event.stream

	prepareStream: ->
		@pc.addStream @localStream

		@pc.createOffer
			offerToReceiveVideo: 1
		.then ((desc) =>
			console.log 'offer created'
			@pc.setLocalDescription(desc)
			.then (() =>
				console.log 'local description set'
				@ws.send JSON.stringify
					type: 'exchangeDescription'
					desc: @pc.localDescription
					source: 'streamer')
			, @logError)
		, @logError
		
	setRemoteDescription: (desc) ->
		console.log 'setremotedescription'
		@pc.setRemoteDescription(desc)
		.then (() => console.log 'remote description set'), @logError

		if @state.viewing
			@pc.createAnswer().then ((_desc) =>
				console.log 'create answer'
				@pc.setLocalDescription(_desc)
				.then (() =>
					console.log 'setLocalDescription'
					@ws.send JSON.stringify
						type: 'exchangeDescription'
						desc: _desc
						source: 'viewer')
				, @logError)
			, @logError

	addIceCandidate: (candidate) ->
		@pc.addIceCandidate(candidate)
		.then (() => console.log 'candidate added'), @logError
	
	logError: (err) -> console.error err

	start: ->
		@setState
			streaming: true

		@setupPC 'streamer'

		navigator.mediaDevices.getUserMedia
			video:
				mandatory:
					minHeight: 270
					maxHeight: 270
					minWidth: 480
					maxWidth: 480
		.then (stream) =>
			@video.srcObject = stream
			@localStream = stream
			@ws.send JSON.stringify
				type: 'startStream'
		.catch (e) =>
			console.error 'Error accessing devices'

	view: ->
		@setState
			viewing: true

		@setupPC 'viewer'

		@ws.send JSON.stringify
			type: 'startView'

	end: ->
		if @state.streaming then type = 'endStream' else type = 'endView'

		@setState
			streaming: false
			viewing: false

		@pc.close()
		@pc = null

		@video.srcObject = null
		@localStream = null

		@ws.send JSON.stringify
			type: type

	getViewButton: ->
		if @state.streaming
			<button disabled>View Stream</button>
		else if @state.viewing
			<button className='view' onClick={@end}>End Viewing</button>
		else
			<button className='view' onClick={@view}>View Stream</button>

	getStreamButton: ->
		if @state.viewing
			<button disabled>Start Stream</button>
		else if @state.streaming
			<button className='stream' onClick={@end}>End Stream</button>
		else
			<button className='stream' onClick={@start}>Start Stream</button>

	render: ->
		<div className='container'>
			<video id='feed' autoPlay></video>
			<div>
				{@getStreamButton()}
				{@getViewButton()}
			</div>
			<div>
				<p>{'Last message sent: ' + @state.lastMessage}</p>
			</div>
		</div>

module.exports = App