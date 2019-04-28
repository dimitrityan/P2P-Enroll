//
//  main.swift
//  P2PEnroll
//
//  Created by Dimitri Tyan on 23.04.19.
//  Copyright © 2019 Dimitri Tyan. All rights reserved.
//

import Foundation
import Socket
import CryptoSwift

let ENROLL_URL = "fulcrum.net.in.tum.de"
let ENROLL_PORT : Int32 = 34151
let CONNECTION_THRESHOLD = 30000000000

let email = "foo@bar.com\r\n"
let firstName = "Dimitri\r\n"
let lastName = "Tyan"

let credentials = email + firstName + lastName

let DHT : UInt16 = 4963
let RPS : UInt16 = 15882
let NSE : UInt16 = 7071
let ONION : UInt16 = 39943

let ENROLL_INIT : UInt16 = 680
let ENROLL_REGISTER : UInt16 = 681
let ENROLL_SUCCESS: UInt16 = 682
let TEAM_NUMBER : UInt16 = 13

enum Project : UInt16 {
    case DHT = 4963
    case RPS = 15882
    case NSE = 7071
    case ONION = 39943
}

enum ServerResponse : UInt16 {
    case ENROLL_INIT = 680
    case ENROLL_REGISTER = 681
    case ENROLL_SUCCESS = 682
}

func createEnrollData(_ challenge: Data, _ teamNumber: Data, _ projectData: Data, _ nonceData: Data, _ credData: Data) -> Data{
    var enrollData = challenge
    enrollData.append(teamNumber)
    enrollData.append(projectData)
    enrollData.append(nonceData)
    enrollData.append(credData)
    return enrollData
}

func reconnect() throws -> Socket {
    print("Reconnecting")
    let socket = try Socket.create()
    try socket.connect(to: ENROLL_URL, port: ENROLL_PORT)
    
    return socket
}

func initConnection() throws {
    let socket = try Socket.create()
    try socket.connect(to: ENROLL_URL, port: ENROLL_PORT)
    var data = Data()
    
    _ = try socket.read(into: &data)
    
    let enrollInit = data[2...3]
    let challenge = data[4...11]
    
    let enrollInitBytes = withUnsafeBytes(of: ServerResponse.ENROLL_INIT.rawValue.bigEndian) { Data($0) }
    
    if enrollInit != enrollInitBytes {
        print("Server response error: expected enroll initialization")
        return
    }
    
    try computeHash(socket: socket, challenge: challenge)
}

func computeHash(socket: Socket, challenge: Data) throws {
    var socket = socket
    var challenge = challenge
    var nonce = Int64(arc4random()) + (Int64(arc4random()) << 32)
    var nonceData = withUnsafeBytes(of: nonce) { Data($0) }
    let teamNumberData = withUnsafeBytes(of: TEAM_NUMBER.bigEndian) { Data($0) }
    let projectData = withUnsafeBytes(of: Project.DHT.rawValue.bigEndian) { Data($0) }
    guard let credData = credentials.data(using: .utf8) else {
        print("Could not create data from String representation")
        return
    }
    
    var enrollData = createEnrollData(challenge, teamNumberData, projectData, nonceData, credData)
    var hash = enrollData.sha256()
    var start = DispatchTime.now()
    var end = DispatchTime.now()
    var elapsedTime = end.uptimeNanoseconds - start.uptimeNanoseconds
    
    // Check if the first 4 Bytes are 0
    while hash[0...3] != withUnsafeBytes(of: UInt32(bigEndian: 0)) { Data($0)} {
        end = DispatchTime.now()
        elapsedTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        if elapsedTime > CONNECTION_THRESHOLD {
            socket = try reconnect()
            var newEnrollResponse = Data()
            _ = try socket.read(into: &newEnrollResponse)
            challenge = newEnrollResponse[4...11]
            start = DispatchTime.now()
        }
        nonce = Int64(arc4random()) + (Int64(arc4random()) << 32)
        nonceData = withUnsafeBytes(of: nonce) { Data($0) }
        enrollData = createEnrollData(challenge, teamNumberData, projectData, nonceData, credData)
        hash = enrollData.sha256()
        print(hash.toHexString())
    }
    
    // First 4 Bytes are 0
    try sendEnrollRegistration(enrollData, socket)
}

func sendEnrollRegistration(_ enrollData: Data, _ socket: Socket) throws {
    var enrollRegisterData = withUnsafeBytes(of: ENROLL_REGISTER.bigEndian) { Data($0) }
    enrollRegisterData.append(enrollData)
    
    var enrollRegisterDataWithSize = withUnsafeBytes(of: UInt16(enrollRegisterData.count + 2).bigEndian) { Data($0) }
    enrollRegisterDataWithSize.append(enrollRegisterData)
    try socket.write(from: enrollRegisterDataWithSize)
    
    var response = Data()
    _ = try socket.read(into: &response)
    
    let successResponseData = withUnsafeBytes(of: ENROLL_SUCCESS.bigEndian) { Data($0) }
    
    if successResponseData != response[2...3] {
        print("Error: \(response.toHexString())")
        return
    }
    
    print("Server response: \(response.toHexString())")
    let team = response[6...7]
    print("Team number: \(team.toHexString())")
}

try initConnection()
