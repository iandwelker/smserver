import Foundation

func main() {
	let server = ServerDelegate()
	let settings = Settings.shared()
	settings.parseArgs()

	guard !settings.show_help else {
		print(Const.help_string)
		exit(0)
	}

	print(server.startServers() ? "Started server & websocket..." : "Failed to start server and websocket...")
	print("Connect to them at http\(settings.is_secure ? "s" : "")://\(Const.getWiFiAddress() ?? "your device's IP Address"):\(settings.server_port)")

	while let string = readLine() {
		if string == "q" { break }
		else {
			print("got line: \(string)")
		}
	}
}

main()
