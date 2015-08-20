express = require('express')
logger = require('logger-sharelatex')
logger.initialize("filestore")
settings = require("settings-sharelatex")
request = require("request")
fileController = require("./app/js/FileController")
keyBuilder = require("./app/js/KeyBuilder")
domain = require("domain")
appIsOk = true
app = express()
streamBuffers = require("stream-buffers")

Metrics = require "metrics-sharelatex"
Metrics.initialize("filestore")
Metrics.open_sockets.monitor(logger)
Metrics.event_loop?.monitor(logger)
#Metrics.memory.monitor(logger)

app.configure ->
	app.use express.bodyParser()
	app.use Metrics.http.monitor(logger)
	
app.configure 'development', ->
	console.log "Development Enviroment"
	app.use express.errorHandler({ dumpExceptions: true, showStack: true })

app.configure 'production', ->
	console.log "Production Enviroment"
	app.use express.errorHandler()

Metrics.inc "startup"

app.use (req, res, next)->
	Metrics.inc "http-request"
	next()

app.use (req, res, next) ->
	requestDomain = domain.create()
	requestDomain.add req
	requestDomain.add res
	requestDomain.on "error", (err)->
		try
			appIsOk = false
			# request a shutdown to prevent memory leaks
			beginShutdown()
			if !res.headerSent
				res.send(500, "uncaught exception")
			logger = require('logger-sharelatex')
			req =
				body:req.body
				headers:req.headers
				url:req.url
				key: req.key
				statusCode: req.statusCode
			err =
				message: err.message
				stack: err.stack
				name: err.name
				type: err.type
				arguments: err.arguments
			logger.err err:err, req:req, res:res, "uncaught exception thrown on request"
		catch exception
			logger.err err: exception, "exception in request domain handler"
	requestDomain.run next

app.use (req, res, next) ->
	if not appIsOk
		# when shutting down, close any HTTP keep-alive connections
		res.set 'Connection', 'close'
	next()

app.get  "/project/:project_id/file/:file_id", keyBuilder.userFileKey, fileController.getFile
app.post "/project/:project_id/file/:file_id", keyBuilder.userFileKey, fileController.insertFile

app.put "/project/:project_id/file/:file_id", keyBuilder.userFileKey, fileController.copyFile
app.del "/project/:project_id/file/:file_id", keyBuilder.userFileKey, fileController.deleteFile

app.get  "/template/:template_id/v/:version/:format", keyBuilder.templateFileKey, fileController.getFile
app.get  "/template/:template_id/v/:version/:format/:sub_type", keyBuilder.templateFileKey, fileController.getFile
app.post "/template/:template_id/v/:version/:format", keyBuilder.templateFileKey, fileController.insertFile


app.get  "/project/:project_id/public/:public_file_id", keyBuilder.publicFileKey, fileController.getFile
app.post "/project/:project_id/public/:public_file_id", keyBuilder.publicFileKey, fileController.insertFile

app.put "/project/:project_id/public/:public_file_id", keyBuilder.publicFileKey, fileController.copyFile
app.del "/project/:project_id/public/:public_file_id", keyBuilder.publicFileKey, fileController.deleteFile

app.get "/heapdump", (req, res)->
	require('heapdump').writeSnapshot '/tmp/' + Date.now() + '.filestore.heapsnapshot', (err, filename)->
		res.send filename

app.post "/shutdown", (req, res)->
	appIsOk = false
	res.send()

app.get '/status', (req, res)->
	if appIsOk
		res.send('filestore sharelatex up')
	else
		logger.log "app is not ok - shutting down"
		res.send("server is being shut down", 500)

app.get "/health_check", (req, res)->
	req.params.project_id = settings.health_check.project_id
	req.params.file_id = settings.health_check.file_id
	myWritableStreamBuffer = new streamBuffers.WritableStreamBuffer(initialSize: 100)
	keyBuilder.userFileKey req, res, ->
		fileController.getFile req, myWritableStreamBuffer
		myWritableStreamBuffer.on "close", ->
			if myWritableStreamBuffer.size() > 0
				res.send(200)
			else
				res.send(503)

app.get '*', (req, res)->
	res.send 404

module.exports = {app:app}
