//
//  test.swift
//  swift-kcp
//
//  Created by rannger on 2018/6/28.
//  Copyright © 2018年 rannger. All rights reserved.
//

import Cocoa

extension Date {
    var millisecondsSince1970:Int {
        return Int((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds:Int) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
    }
}

class Random : NSObject {
    var size : Int
    var seeds : Array<Int>
    
    override init() {
        self.size = 0
        self.seeds = [Int]()
    }
    
    init(sz:Int) {
        self.size = 0
        self.seeds = [Int](repeating: 0, count: sz)
    }
    
    func random() -> Int {
        if self.seeds.count == 0 {
            return 0
        }
        if 0 == self.size {
            for i in 0..<self.seeds.count {
                seeds[i] = i
            }
            size = self.seeds.count
        }
        let i = Int(arc4random()) % self.size
        let x = self.seeds[i]
        seeds[i] = seeds[self.size - 1]; self.size -= 1;
        return x
    }
}

class DelayPacket: NSObject {
    var ts = uint32(0)
    var data : Data
    init(dt:Data) {
        self.data = dt
    }
}

func isleep(millisecond:uint32) -> Void {
    usleep(useconds_t((millisecond << 10) - (millisecond << 4) - (millisecond << 3)))
}

class LatencySimulator: NSObject {
    var current : uint32
    var lostrate : Int
    var rttmin : Int
    var rttmax : Int
    var nmax : Int
    var p12 : Array<DelayPacket>
    var p21 : Array<DelayPacket>
    var r12 : Random
    var r21 : Random
    
    var tx1 : Int
    var tx2 : Int
    
    init(lostrate:Int = 10,rttmin:Int = 60,rttmax:Int = 125,nmax:Int = 1000) {
        self.r12 = Random(sz: 100)
        self.r21 = Random(sz: 100)
        
        self.current = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
        self.lostrate = lostrate / 2
        self.rttmin = rttmin / 2
        self.rttmax = rttmax / 2
        self.nmax = nmax
        self.tx1 = 0
        self.tx2 = 0
        
        self.p12 = Array<DelayPacket>()
        self.p21 = Array<DelayPacket>()
    }
    
    func clear() -> Void {
        self.p21.removeAll()
        self.p12.removeAll()
    }
   
    func send(peer:Int,dt:Data) -> Void {
        if 0 == peer {
            self.tx1 += 1
            if r12.random() < lostrate {
                return
            }
            if p12.count >= nmax {
                return
            }
        } else {
            self.tx2 += 1
            if r21.random() < lostrate {
                return
            }
            if p21.count >= nmax {
                return
            }
        }
        
        let pkt = DelayPacket(dt: dt)
        self.current = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
        var delay = uint32(self.rttmin)
        if rttmax > rttmin {
            delay += (uint32(arc4random()) % uint32(rttmax - rttmin))
        }
        pkt.ts = self.current + delay
        if 0 == peer {
            p12.append(pkt)
        } else {
            p21.append(pkt)
        }
    }
    
    func recv(peer:Int) -> Data? {
        var pkt : DelayPacket? = nil
        if 0 == peer {
            if 0 == self.p21.count {
                return nil
            }
            
            pkt = self.p21.first
        } else {
            if 0 == p12.count {
                return nil
            }
            pkt = self.p12.first
        }
        self.current = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
        if self.current < pkt!.ts {
            return nil
        }
        if 0 == peer {
            self.p21.remove(at: 0)
        } else {
            self.p12.remove(at: 0)
        }
        return pkt!.data
    }
}

var vnet : LatencySimulator? = nil

func udp_output(buf:[uint8],kcp:inout IKCPCB,user:uint64) -> Int {
    vnet?.send(peer: Int(user), dt: Data(bytes: buf))
    return 0
}

func test(mode:Int) -> Void {
    vnet = LatencySimulator(lostrate: 10, rttmin: 60, rttmax: 125)
    var kcp1 = IKCPCB.init(conv: 0x11223344, user: 0)
    var kcp2 = IKCPCB.init(conv: 0x11223344, user: 1)
    kcp1.output = udp_output
    kcp2.output = udp_output
    
    var current = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
    var slap = current + 20
    var index = uint32(0)
    var next = uint32(0)
    var sumrtt = uint32(0)
    var count = Int(0)
    var maxrtt = Int(0)
    
    _ = kcp1.wndSize(sndwnd: 128, rcvwnd: 128)
    _ = kcp2.wndSize(sndwnd: 128, rcvwnd: 128)
    
    if 0 == mode {
        _ = kcp1.nodelay(nodelay: 0, internalVal: 10, resend: 0, nc: 0)
        _ = kcp2.nodelay(nodelay: 0, internalVal: 10, resend: 0, nc: 0)
    } else if 1 == mode{
        _ = kcp1.nodelay(nodelay: 0, internalVal: 10, resend: 0, nc: 1)
        _ = kcp2.nodelay(nodelay: 0, internalVal: 10, resend: 0, nc: 1)
    } else {
        
        _ = kcp1.nodelay(nodelay: 1, internalVal: 10, resend: 2, nc: 1)
        _ = kcp2.nodelay(nodelay: 1, internalVal: 10, resend: 2, nc: 1)
        kcp1.rx_minrto = 10
        kcp1.fastresend = 1
    }
   
    var buffer = [uint8](repeating: 0, count: 2000)
    var ts1 = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
    while true {
        isleep(millisecond: 1)
        current = uint32(truncating: NSNumber(value: Date().millisecondsSince1970))
        kcp1.update(current: uint32(truncating: NSNumber(value: Date().millisecondsSince1970)))
        kcp2.update(current: uint32(truncating: NSNumber(value: Date().millisecondsSince1970)))
        while current >= slap {
            repeat {
                var littleEndian = index.littleEndian
                let count = MemoryLayout<UInt32>.size
                let bytePtr = withUnsafePointer(to: &littleEndian) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                        UnsafeBufferPointer(start: $0, count: count)
                    }
                }
                let byteArray = Array(bytePtr)
                index += 1
                for i in 0..<4 {
                    buffer[i] = byteArray[i]
                }
            } while false

            repeat {
                var littleEndian = current.littleEndian
                let count = MemoryLayout<UInt32>.size
                let bytePtr = withUnsafePointer(to: &littleEndian) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                        UnsafeBufferPointer(start: $0, count: count)
                    }
                }
                let byteArray = Array(bytePtr)
                for i in 0..<4 {
                    buffer[i+4] = byteArray[i]
                }
            } while false
            
            let dt = Data(bytes: UnsafeRawPointer(UnsafeMutablePointer(mutating: buffer)), count: 8)
            _ = kcp1.send(buffer: dt)
            slap += 20
        }
        
        while true {
            let hr = vnet?.recv(peer: 1)
            if nil == hr {
                break
            }
            _ = kcp2.input(data: hr!)
        }
        
        while true {
            let hr = vnet?.recv(peer: 0)
            if nil == hr {
                break
            }
            _ = kcp1.input(data: hr!)
        }
        
        while true {
            let hr = kcp2.recv(dataSize: 10)
            if nil == hr {
                break
            }
            _ = kcp2.send(buffer: hr!)
        }
        
        while true {
            let hr = kcp1.recv(dataSize: 10)
            if nil == hr {
                break
            }
            let buffer = [uint8](hr!)
            let sn = UInt32(littleEndian: Data(bytes: buffer, count: 4).withUnsafeBytes { $0.pointee })
            let ts = UInt32(littleEndian: Data(bytes: [uint8](buffer[4...7]), count: 4).withUnsafeBytes { $0.pointee })
            let rtt = current - ts
            if sn != next {
                NSLog("ERROR sn \(count)<->\(next)\n")
                return
            }
            
            next += 1
            sumrtt += rtt
            count += 1
            if rtt > maxrtt {
                maxrtt = Int(rtt)
            }
            
//            NSLog("[RECV] mode=\(mode) sn=\(sn) rtt=\(rtt)\n");
        }
        if next > 1000 {
            break
        }
    }
    
    ts1 = uint32(truncating: NSNumber(value: Date().millisecondsSince1970)) - ts1
    
    let names = [ "default", "normal", "fast" ]
    NSLog("\(names[mode]) mode result (\(ts1)ms):\n");
    NSLog("avgrtt=\(Int(sumrtt) / Int(count)) maxrtt=\(maxrtt) tx=\(vnet!.tx1)\n");
}

test(mode: 0);    // 默认模式，类似 TCP：正常模式，无快速重传，常规流控
test(mode: 1);    // 普通模式，关闭流控等
test(mode: 2); // 快速模式，所有开关都打开，且关闭流控

