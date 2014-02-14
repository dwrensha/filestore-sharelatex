assert = require("chai").assert
sinon = require('sinon')
chai = require('chai')
should = chai.should()
expect = chai.expect
modulePath = "../../../app/js/s3Wrapper.js"
SandboxedModule = require('sandboxed-module')

describe "s3WrapperTests", ->

	beforeEach ->
		@settings = 
			s3:
				secret: "secret"
				key: "this_key"
			buckets:
				user_files:"sl_user_files"
		@stubbedKnoxClient = 
			putFile:sinon.stub()
			copyFile:sinon.stub()
			list: sinon.stub()
			deleteMultiple: sinon.stub()
		@knox = 
			createClient: sinon.stub().returns(@stubbedKnoxClient)
		@LocalFileWriter = 
			writeStream: sinon.stub()
			deleteFile: sinon.stub()
		@requires = 
			"knox": @knox
			"settings-sharelatex": @settings
			"./LocalFileWriter":@LocalFileWriter
			"logger-sharelatex":
				log:->
				err:->
		@key = "my/key"
		@bucketName = "my-bucket"
		@error = "my errror"

	describe "Pipe to dest", ->

		it "should use correct options", (done)->

			stubbedReadStream = {on:->}
			dest = {my:"object"}
			@request = (opts)=>
				return stubbedReadStream
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires
			@s3Wrapper.getFileStream @bucketName, @key, (err, readStream)->
				readStream.should.equal stubbedReadStream
				done()

	describe "sendFileToS3", ->

		beforeEach ->
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires
			@stubbedKnoxClient.putFile.returns on:->

		it "should put file with knox", (done)->
			@LocalFileWriter.deleteFile.callsArgWith(1)
			@stubbedKnoxClient.putFile.callsArgWith(2, @error)
			@s3Wrapper.sendFileToS3 @bucketName, @key, @fsPath, (err)=>
				@stubbedKnoxClient.putFile.calledWith(@fsPath, @key).should.equal true
				err.should.equal @error
				done()

		it "should delete the file and pass the error with it", (done)->
			@LocalFileWriter.deleteFile.callsArgWith(1)
			@stubbedKnoxClient.putFile.callsArgWith(2, @error)
			@s3Wrapper.sendFileToS3 @bucketName, @key, @fsPath, (err)=>
				@stubbedKnoxClient.putFile.calledWith(@fsPath, @key).should.equal true
				err.should.equal @error
				done()

	describe "sendStreamToS3", ->
		beforeEach ->
			@fsPath = "to/some/where"
			@origin = 
				on:->
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires
			@s3Wrapper.sendFileToS3 = sinon.stub().callsArgWith(3)

		it "should send stream to LocalFileWriter", (done)->
			@LocalFileWriter.deleteFile.callsArgWith(1)
			@LocalFileWriter.writeStream.callsArgWith(2, null, @fsPath)
			@s3Wrapper.sendStreamToS3 @bucketName, @key, @origin, =>
				@LocalFileWriter.writeStream.calledWith(@origin).should.equal true
				done()

		it "should return the error from LocalFileWriter", (done)->
			@LocalFileWriter.deleteFile.callsArgWith(1)
			@LocalFileWriter.writeStream.callsArgWith(2, @error)
			@s3Wrapper.sendStreamToS3 @bucketName, @key, @origin, (err)=>
				err.should.equal @error
				done()

		it "should send the file to s3", (done)->
			@LocalFileWriter.deleteFile.callsArgWith(1)
			@LocalFileWriter.writeStream.callsArgWith(2)
			@s3Wrapper.sendStreamToS3 @bucketName, @key, @origin, (err)=>
				@s3Wrapper.sendFileToS3.called.should.equal true
				done()

	describe "copyFile", ->
		beforeEach ->
			@sourceKey = "my/key"
			@destKey = "my/dest/key"
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

		it "should use knox to copy file", (done)->
			@stubbedKnoxClient.copyFile.callsArgWith(2, @error)
			@s3Wrapper.copyFile @bucketName, @sourceKey, @destKey, (err)=>
				err.should.equal @error
				@stubbedKnoxClient.copyFile.calledWith(@sourceKey, @destKey).should.equal true
				done()

	describe "deleteDirectory", ->

		beforeEach ->
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

		it "should list the contents passing them onto multi delete", (done)->
			data = 
				Contents: [{Key:"1234"}, {Key: "456"}]
			@stubbedKnoxClient.list.callsArgWith(1, null, data)
			@stubbedKnoxClient.deleteMultiple.callsArgWith(1)
			@s3Wrapper.deleteDirectory @bucketName, @key, (err)=>
				@stubbedKnoxClient.deleteMultiple.calledWith(["1234","456"]).should.equal true
				done()

	describe "deleteFile", ->

		it "should use correct options", (done)->
			@request = sinon.stub().callsArgWith(1)
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

			@s3Wrapper.deleteFile @bucketName, @key, (err)=>
				opts = @request.args[0][0]
				assert.deepEqual(opts.aws, {key:@settings.s3.key, secret:@settings.s3.secret, bucket:@bucketName})
				opts.method.should.equal "delete"
				opts.timeout.should.equal (30*1000)
				opts.uri.should.equal "https://#{@bucketName}.s3.amazonaws.com/#{@key}"
				done()

		it "should return the error", (done)->
			@request = sinon.stub().callsArgWith(1, @error)
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

			@s3Wrapper.deleteFile @bucketName, @key, (err)=>
				err.should.equal @error
				done()

	describe "checkIfFileExists", ->

		it "should use correct options", (done)->
			@request = sinon.stub().callsArgWith(1,  null, statusCode:200)
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

			@s3Wrapper.checkIfFileExists @bucketName, @key, (err)=>
				opts = @request.args[0][0]
				assert.deepEqual(opts.aws, {key:@settings.s3.key, secret:@settings.s3.secret, bucket:@bucketName})
				opts.method.should.equal "head"
				opts.timeout.should.equal (30*1000)
				opts.uri.should.equal "https://#{@bucketName}.s3.amazonaws.com/#{@key}"
				done()

		it "should return true for a 200", (done)->
			@request = sinon.stub().callsArgWith(1, null, statusCode:200)
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires
			@s3Wrapper.checkIfFileExists @bucketName, @key, (err, exists)=>
				exists.should.equal true
				done()

		it "should return false for a non 200", (done)->
			@request = sinon.stub().callsArgWith(1, null, statusCode:404)
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires
			@s3Wrapper.checkIfFileExists @bucketName, @key, (err, exists)=>
				exists.should.equal false
				done()

		it "should return the error", (done)->
			@request = sinon.stub().callsArgWith(1, @error, {})
			@requires["request"] = @request
			@s3Wrapper = SandboxedModule.require modulePath, requires: @requires

			@s3Wrapper.checkIfFileExists @bucketName, @key, (err)=>
				err.should.equal @error
				done()