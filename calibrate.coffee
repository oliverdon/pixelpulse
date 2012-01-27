# Firmware update
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

app = (window.app ?= {})

app.init = (server, params) ->
	server.connect()

	server.disconnected.listen ->
		$(document.body).html("Disconnected")

	server.devicesChanged.listen (l) ->
		app.chooseDevice()
		
	app.chooseDevice()
	
log = (el, success) ->
	c = {}
	if success? then c = {color: if success then 'green' else 'red'}
	$('<div>').append(el).css(c).appendTo('#log')
	window.scrollTo(0, document.body.scrollHeight)
		
app.chooseDevice = ->
	for dev in server.devices
		if dev.model == 'com.nonolithlabs.cee'
			return onCEE(server.selectDevice(dev))
		else if dev.model == 'com.nonolithlabs.bootloader'
			return onBootloaderDevice(server.selectDevice(dev))


testing_serial = null

startWithDevice = (dev) ->
	unless testing_serial is dev.serial
		testing_serial = dev.serial
		log($("<h1>").text(dev.serial))

# Bootloader: flash code 

onBootloaderDevice = (dev) ->
	erase = (cb) ->
		dev.erase (m) ->
			log("Erased")
			if $.isFunction(cb) then cb()
		
	checkCRC = (cb) ->
		dev.crcApp (m) ->
			valid = (m.crc == firmware.crc)
			vs = if valid then 'Valid' else 'INVALID'
			console.log(m.crc, firmware.crc)
			log("App CRC: #{m.crc} - #{vs}", valid)
			if $.isFunction(cb) then cb(valid)

	write = (cb) ->
		server.device.write firmware.data, (m) ->
			success = (m.result > 0)
			log("Wrote flash, status #{m.result}", success)
			if $.isFunction(cb) and success then cb()

	flash_and_check = ->
		checkCRC (v) ->
			unless v
				erase ->
					write ->
						checkCRC (v) ->
							if v then server.device.reset()
			else
				server.device.reset()
	
	dev.changed.subscribe ->
		startWithDevice(dev)
		flash_and_check()

# CEE

onCEE = (dev) ->
	changedCount = 0
	changedCb = null
	dev.changed.subscribe ->
		if changedCount == 0
			startWithDevice(dev)
			log("Found CEE #{dev.hwVersion}, #{dev.fwVersion}")	
			runNextTest()
		else
			dev.startCapture()
			changedCb()
		changedCount += 1
	
	changeRaw = (raw, cb) ->
		console.log('changeRaw', raw, cb)
		dev.configure(0, 0.00004, 250000, true, raw)
		changedCb = cb
	
	data = {a:{}, b:{}}
	
	zeroOffset = ->
		offsetAt = (setval, cb) ->
			testStream = (channel, stream, cb) ->
				stream.getSample 0.5, (d) ->
					target = if stream.id is 'v'
						setval/2
					else
						0
						
					success = Math.abs(d-target) < 100
					log("Channel #{channel.id} #{stream.id} offset at #{setval} is #{d} (#{d-target})LSB", success)
					data[channel.id].offset ?= {}
					data[channel.id].offset[stream.id] = d
					cb()
					
			dev.channels.a.setConstant 1, setval, ->
				async.parallel [
					(cb) -> testStream(dev.channels.a, dev.channels.a.streams.v, cb)
					(cb) -> testStream(dev.channels.a, dev.channels.a.streams.i, cb)
					(cb) -> testStream(dev.channels.b, dev.channels.b.streams.v, cb)
					(cb) -> testStream(dev.channels.b, dev.channels.b.streams.i, cb)
				], cb
			
		
		async.series [
			(cb) -> changeRaw(true, cb)
			(cb) -> dev.channels.b.setConstant(3, 0, cb)
			(cb) -> setTimeout(cb, 100)
			(cb) -> offsetAt(0, cb)
			(cb) -> offsetAt(800, cb)
			(cb) -> offsetAt(2400, cb)
			(cb) -> offsetAt(4096, cb)
			
		], runNextTest
		
	measureCSAError = ->
		runNextTest()
		
		
	calibrateIset = ->
		calibrate = (channel, target, cb) ->
			dacval = 2000
			otherdac = 0
			stepsize = 100
			
			above = false
			count = 0
			
			step = ->
				[daca, dacb] = if channel.id is 'a' then [dacval, otherdac] else [otherdac, dacval]
				#console.log("setting", Math.round(daca), Math.round(dacb))
				dev.controlTransfer 0xC0, 0x15, Math.round(daca), Math.round(dacb), [], 0, ->
					channel.streams.i.getSample 0.02, (d) ->
						#console.log("got", d)
						
						if stepsize <= 1
							log("ISET DAC #{channel.id} #{target}ma is #{dacval}", true)
							data[channel.id].iset ?= {}
							data[channel.id].iset[target] = dacval
							return cb()
						
						nabove = d>target	
						if above != nabove
							stepsize /= 2
							above = nabove
						
						dacval = Math.round(dacval + if above then stepsize else -stepsize)
						
						count += 1
						
						if dacval < 1500 or count > 100
							log("DACVAL too far, #{count}", false)
							cb()
						else
							step()
			step()
							
		
		async.series [
			(cb) -> changeRaw(false, cb)
			(cb) -> dev.channels.b.setConstant(1, 0, cb)
			(cb) -> dev.channels.a.setConstant(1, 5, cb)
			(cb) -> calibrate(dev.channels.a, 200, cb)
			(cb) -> calibrate(dev.channels.a, 400, cb)
			(cb) -> dev.channels.a.setConstant(1, 0, cb)
			(cb) -> dev.channels.b.setConstant(1, 5, cb)
			(cb) -> calibrate(dev.channels.b, 200, cb)
			(cb) -> calibrate(dev.channels.b, 400, cb)
		], runNextTest
	
	writeEEPROM = ->
		log("Not writing eeprom", false)
		runNextTest()
		
	tests = [
		zeroOffset
		measureCSAError
		calibrateIset
		writeEEPROM
	]
	
	runNextTest = ->
		if tests.length
			tests.shift()()
		else
			testingDone()
			log("Testing complete", true)
			saveData()
			
	testingDone = ->
		dev.pauseCapture()
			
	saveData = ->
		console.log(data)
		log("Did not save data", false)
	
			
				
app.set_fw = (fw) ->
	window.firmware = fw
	log("Loaded firmware for #{firmware.device} #{firmware.hwversion}, CRC = #{firmware.crc}", true)
	
$(document).ready ->		
	app.init(server)
	$.get('cee.json', app.set_fw, 'json')
