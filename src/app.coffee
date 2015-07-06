connman = require('connman-simplified')()
express = require('express')
app = express()
bodyParser = require('body-parser')
_ = require('lodash')
iptables = require('./iptables')

exec = require('child_process').exec

ssid = process.env.SSID or 'ResinAP'
passphrase = process.env.PASSPHRASE or '12345678'

port = process.env.PORT or 8080

server = null
ssidList = null

os = require('os')

iptablesRules = ->
	myIP = os.networkInterfaces().tether[0].address
	return [
			table: 'nat'
			chain: 'PREROUTING'
			protocol: 'tcp'
			interface: 'tether'
			dport: '80'
			jump: 'DNAT'
			target_options: 'to-destination': "#{myIP}:8080"
		,
			table: 'nat'
			chain: 'PREROUTING'
			protocol: 'tcp'
			interface: 'tether'
			dport: '443'
			jump: 'DNAT'
			target_options: 'to-destination': "#{myIP}:8080"
	]


console.log("Starting node connman app")
connman.init (err) ->
	throw err if err?
	console.log("Connman initialized")
	connman.initWiFi (err, wifi, properties) ->
		openHotspot = (ssid, passphrase, cb) ->
			# Reload bcm4334x with op_mode=2, the trick for 
			# tethering to work on Edison
			_.delay exec, 500, "modprobe -r bcm4334x", (err) ->
				return cb(err) if err?
				_.delay exec, 500, "modprobe bcm4334x op_mode=2", (err) ->
					return cb(err) if err?
					_.delay wifi.openHotspot, 1000, ssid, passphrase, (err) ->
						return cb(err) if err?
						# Add wlan0 to the bridge because connman has a bug.
						exec "brctl addif tether wlan0", cb

		closeHotspot = (err) ->
			wifi.closeHotspot (err) ->
				_.delay exec, 500, "modprobe -r bcm4334x", (err) ->
					return cb(err) if err?
					_.delay exec, 500, "modprobe bcm4334x", cb

		startServer = (wifi) ->
			wifi.getNetworks (err, list) ->
				throw err if err?
				ssidList = list
				openHotspot ssid, passphrase, (err) ->
					throw err if err?
					console.log("Hotspot enabled")
					iptables.appendMany iptablesRules(), (err) ->
						throw err if err?
						console.log("Captive portal enabled")
						server = app.listen port, ->
							console.log("Server listening")

		throw err if err?
		console.log("WiFi initialized")

		app.use(bodyParser())
		app.use(express.static(__dirname + '/public'))
		app.get '/ssids', (req, res) ->
			res.send(ssidList)
		app.post '/connect', (req, res) ->
			if req.body.ssid and req.body.passphrase
				console.log("Selected " + req.body.ssid)
				res.send('OK')
				server.close ->
					iptables.deleteMany iptablesRules(), (err) ->
						throw err if err?
						closeHotspot (err) ->
							throw err if err?
							console.log("Server closed and captive portal disabled")
							_.delay wifi.joinWithAgent, 1000, req.body.ssid, req.body.passphrase, (err) ->
								console.log(err) if err
								return startServer(wifi) if err
								console.log("Joined! Exiting.")
								process.exit()

		if !properties.connected
			console.log("Not connected, starting AP")
			startServer(wifi)
		else
			console.log("Already connected")
			process.exit()
					

							

