//
//  kcp.swift
//  swift-kcp
//
//  Created by rannger on 2018/6/22.
//  Copyright © 2018年 rannger. All rights reserved.
//

import Cocoa

extension Array {
    mutating func removeAtIndexes(indexes: NSIndexSet) {
        var i = indexes.lastIndex
        while i != NSNotFound {
            self.remove(at: i)
            i = indexes.indexLessThanIndex(i)
        }
    }
}


//=====================================================================
// KCP BASIC
//=====================================================================
let IKCP_RTO_NDL : uint32 = 30        // no delay min rto
let IKCP_RTO_MIN : uint32 = 100        // normal min rto
let IKCP_RTO_DEF : uint32 = 200
let IKCP_RTO_MAX : uint32 = 60000
let IKCP_CMD_PUSH : uint32 = 81        // cmd: push data
let IKCP_CMD_ACK  : uint32 = 82        // cmd: ack
let IKCP_CMD_WASK : uint32 = 83        // cmd: window probe (ask)
let IKCP_CMD_WINS : uint32 = 84        // cmd: window size (tell)
let IKCP_ASK_SEND : uint32 = 1        // need to send IKCP_CMD_WASK
let IKCP_ASK_TELL : uint32 = 2        // need to send IKCP_CMD_WINS
let IKCP_WND_SND : uint32 = 32
let IKCP_WND_RCV : uint32 = 128       // must >: uint32 = max fragment size
let IKCP_MTU_DEF : uint32 = 1400
let IKCP_ACK_FAST : uint32 = 3
let IKCP_INTERVAL : uint32 = 100
let IKCP_OVERHEAD : uint32 = 24
let IKCP_DEADLINK : uint32 = 20
let IKCP_THRESH_INIT : uint32 = 2
let IKCP_THRESH_MIN : uint32 = 2
let IKCP_PROBE_INIT : uint32 = 7000        // 7 secs to probe window size
let IKCP_PROBE_LIMIT : uint32 = 120000    // up to 120 secs to probe window

let IKCP_LOG_OUTPUT : Int         = 1
let IKCP_LOG_INPUT : Int          = 2
let IKCP_LOG_SEND : Int           = 4
let IKCP_LOG_RECV : Int           = 8
let IKCP_LOG_IN_DATA : Int        = 16
let IKCP_LOG_IN_ACK : Int         = 32
let IKCP_LOG_IN_PROBE : Int       = 64
let IKCP_LOG_IN_WINS : Int        = 128
let IKCP_LOG_OUT_DATA : Int       = 256
let IKCP_LOG_OUT_ACK : Int        = 512
let IKCP_LOG_OUT_PROBE : Int      = 1024
let IKCP_LOG_OUT_WINS : Int       = 2048
let IKCP_LOG_ALL : Int            = 4095

fileprivate func _ibound_(lower:uint32,middle:uint32,upper:uint32) -> uint32 {
    return min(max(lower, middle), upper)
}

fileprivate func timeDiff(later:uint32,earlier:uint32) -> sint32 {
    return sint32(later) - sint32(earlier)
}

fileprivate func KCPEncode8u(p:UnsafeMutablePointer<uint8>,c:uint8) -> UnsafeMutablePointer<uint8> {
    p.pointee = c
    return p+1
}

fileprivate func KCPDecode8u(p:UnsafeMutablePointer<uint8>,
                 c:UnsafeMutablePointer<uint8>) -> UnsafePointer<uint8> {
    c.pointee = p.pointee
    return UnsafePointer(p+1)
}

fileprivate func KCPEncode16u(p:UnsafeMutablePointer<uint8>,w:uint16) -> UnsafeMutablePointer<uint8> {
    var bigEndian = w.littleEndian
    let count = MemoryLayout<uint16>.size
    let bytePtr = withUnsafePointer(to: &bigEndian) {
        $0.withMemoryRebound(to: UInt8.self, capacity: count) {
            UnsafeBufferPointer(start: $0, count: count)
        }
    }
    let byteArray = Array(bytePtr)
    for i in 0..<2 {
        (p+i).pointee = byteArray[i]
    }
    return p+2
}

fileprivate func KCPDecode16u(p:UnsafeMutablePointer<uint8>,
                  w:UnsafeMutablePointer<uint16>) -> UnsafePointer<uint8> {
    let size = 2
    var buf = [uint8](repeating: 0, count: size)
    for i in 0..<size {
        buf[i] = (p+i).pointee
    }
    let data = Data(bytes: buf)
    switch CFByteOrderGetCurrent() {
    case CFByteOrder(CFByteOrderLittleEndian.rawValue):
        let value = uint16(littleEndian: data.withUnsafeBytes { $0.pointee })
        w.pointee = value
        break
    case CFByteOrder(CFByteOrderBigEndian.rawValue):
        let value = uint16(bigEndian: data.withUnsafeBytes { $0.pointee })
        w.pointee = value
        break
    default:
        break;
    }
    
    return UnsafePointer(p+size)
}

fileprivate func KCPEncode32u(p:UnsafeMutablePointer<uint8>,l:uint32) -> UnsafeMutablePointer<uint8>  {
    
    var bigEndian = l.littleEndian
    let count = MemoryLayout<UInt32>.size
    let bytePtr = withUnsafePointer(to: &bigEndian) {
        $0.withMemoryRebound(to: UInt8.self, capacity: count) {
            UnsafeBufferPointer(start: $0, count: count)
        }
    }
    let byteArray = Array(bytePtr)
    for i in 0..<4 {
        (p+i).pointee = byteArray[i]
    }

    return p+4
}

fileprivate func KCPDecode32u(p:UnsafeMutablePointer<uint8>,
                  l:UnsafeMutablePointer<uint32>) -> UnsafePointer<uint8> {
    let size = 4
    var buf = [uint8](repeating: 0, count: size)
    for i in 0..<size {
        buf[i] = (p+i).pointee
    }
    let data = Data(bytes: buf)
    switch CFByteOrderGetCurrent() {
    case CFByteOrder(CFByteOrderLittleEndian.rawValue):
        let value = UInt32(littleEndian: data.withUnsafeBytes { $0.pointee })
        l.pointee = value
        break
    case CFByteOrder(CFByteOrderBigEndian.rawValue):
        let value = UInt32(bigEndian: data.withUnsafeBytes { $0.pointee })
        l.pointee = value
        break
    default:
        break;
    }

    return UnsafePointer(p+size)
}

struct IKCPSEG {
    var conv: uint32 = 0
    var cmd: uint32 = 0
    var frg: uint32 = 0
    var wnd: uint32 = 0
    var ts: uint32 = 0
    var sn: uint32 = 0
    var una: uint32 = 0
    var resendts: uint32 = 0
    var rto: uint32 = 0
    var fastack: uint32 = 0
    var xmit: uint32 = 0
    var data: [uint8]
    
    init(size:Int) {
        self.data = [uint8](repeating: 0, count: size)
    }
    
    init() {
        self.data = Array<uint8>()
    }
    
    func encode() -> Data {
        let buf = [uint8](repeating: 0, count: 4*5+2+2)
        var ptr = UnsafeMutablePointer(mutating: buf)
        ptr = KCPEncode32u(p: ptr, l: self.conv)
        ptr = KCPEncode8u(p: ptr, c: uint8(self.cmd))
        ptr = KCPEncode8u(p: ptr, c: uint8(self.frg))
        ptr = KCPEncode16u(p: ptr, w: uint16(self.wnd))
        ptr = KCPEncode32u(p: ptr, l: self.ts)
        ptr = KCPEncode32u(p: ptr, l: self.sn)
        ptr = KCPEncode32u(p: ptr, l: self.una)
        ptr = KCPEncode32u(p: ptr, l: uint32(self.data.count))
        return Data(bytes: buf)
    }
}

fileprivate func DefaultOutput(buf:[uint8],kcp:inout IKCPCB,user:uint64) -> Int {
    return 0;
}

fileprivate func DefaultWritelog(logStr:String,kcp:inout IKCPCB,user:uint64) -> Void {
    print(logStr)
}

class IKCPCB {
    var conv = uint32(0)
    var mtu = uint32(0)
    var mss = uint32(0)
    var state = uint32(0)
    
    var snd_una = uint32(0)
    var snd_nxt = uint32(0)
    var rcv_nxt = uint32(0)
    
    var ts_recent = uint32(0)
    var ts_lastack = uint32(0)
    var ssthresh = uint32(0)
    
    var rx_rttval = uint32(0)
    var rx_srtt = uint32(0)
    var rx_rto = uint32(0)
    var rx_minrto = uint32(0)
    
    var snd_wnd = uint32(0)
    var rcv_wnd = uint32(0)
    var rmt_wnd = uint32(0)
    var cwnd = uint32(0)
    var probe = uint32(0)
    
    var current = uint32(0)
    var interval = uint32(0)
    var ts_flush = uint32(0)
    var xmit = uint32(0)

    var nodelay = uint32(0)
    var updated = uint32(0)
    
    var ts_probe = uint32(0)
    var probe_wait = uint32(0)
    
    var dead_link = uint32(0)
    var snd_queue : [IKCPSEG]
    var rcv_queue : [IKCPSEG]
    var snd_buf : [IKCPSEG]
    var rcv_buf: [IKCPSEG]
    var incr = uint32(0)
    var acklist : [uint32]
    var ackcount = uint32(0)
    var ackblock = uint32(0)
    var buffer: [uint8]
    var user = uint64(0)
    var fastresend = Int(0)
    var nocwnd = Int(0)
    var stream = Int(0)
    var logmask = Int(0)
    
    var output : (([uint8],inout IKCPCB,uint64) -> Int)?
    var writelog: ((String,inout IKCPCB,uint64) -> Void)?
    
    init(conv:uint32,user:uint64) {
        
        self.conv = conv
        self.user = user
        self.snd_wnd = IKCP_WND_SND
        self.rcv_wnd = IKCP_WND_RCV
        self.rmt_wnd = IKCP_WND_RCV
        self.mtu = IKCP_MTU_DEF
        self.mss = self.mtu - IKCP_OVERHEAD
        self.rx_rto = IKCP_RTO_DEF
        self.rx_minrto = IKCP_RTO_MIN
        self.interval = IKCP_INTERVAL
        self.ts_flush = IKCP_INTERVAL
        self.ssthresh = IKCP_THRESH_INIT
        self.dead_link = IKCP_DEADLINK
        self.snd_queue = [IKCPSEG]()
        self.rcv_queue = [IKCPSEG]()
        self.snd_buf = [IKCPSEG]()
        self.rcv_buf = [IKCPSEG]()

        self.buffer = [uint8](repeating: 0, count: Int((self.mtu + IKCP_OVERHEAD)*3))
        self.acklist = [uint32]()
        self.output = DefaultOutput
        self.writelog = DefaultWritelog
    }
    
    func recv(dataSize:Int) -> Data? {
        var recover = false
        if self.rcv_queue.isEmpty {
            return nil
        }
        
        if dataSize == 0 {
            return nil
        }
        
        let peeksize = self.peekSize()
        if peeksize < 0 {
            return nil
        }
        
        if peeksize > dataSize {
            return nil
        }
        
        if self.rcv_queue.count >= self.rcv_wnd {
            recover = true
        }
        var len = Int(0)
        let ispeek = (dataSize < 0)
        let localBuffer = [uint8](repeating: 0, count: dataSize)
        var buf = UnsafeMutablePointer(mutating: localBuffer)
        
        let indexSet = NSMutableIndexSet()
        for i in 0..<self.rcv_queue.count {
            var seg = self.rcv_queue[Int(i)]
            
            var fragment = uint32(0)
            for i in 0..<seg.data.count {
                buf.pointee = seg.data[Int(i)]
                buf += 1
            }
            
            len += seg.data.count
            fragment = seg.frg
            
            if self.canlog(mask: IKCP_LOG_RECV) {
                self.log(mask: IKCP_LOG_RECV, fmt: "recv sn=%lu", seg.sn)
            }
            
            if !ispeek {
                indexSet.add(i)
            }
            
            if 0 == fragment{
                break
            }
        }
        
        self.rcv_queue.removeAtIndexes(indexes: indexSet)
        assert(len == peeksize)
        
        while 0 != self.rcv_buf.count {
            let seg = self.rcv_buf.first!
            if seg.sn == self.rcv_nxt && self.rcv_queue.count < self.rcv_wnd {
                self.rcv_buf.remove(at: 0)
                self.rcv_queue.append(seg)
                self.rcv_nxt += 1
            } else {
                break
            }
        }
        
        if self.rcv_queue.count < self.rcv_wnd && recover {
            self.probe |= IKCP_ASK_TELL
        }
        var temp = [uint8](repeating: 0, count: len)
        for i in 0..<len {
            temp[i] = localBuffer[i]
        }
        return Data(bytes: temp)
    }
    
    func peekSize() -> Int {
        if self.rcv_queue.isEmpty {
            return -1
        }
        let seg = self.rcv_queue.first!
        if 0 == seg.frg {
            return seg.data.count
        }
        if self.rcv_queue.count < seg.frg + 1 {
            return -1
        }
        var length = Int(0)
        for seg in self.rcv_queue {
            length += seg.data.count
            if 0 == seg.frg {
                break
            }
        }
        return 0
    }
    func send(buffer:Data) -> Int {
        let buf = [uint8](repeating: 0, count: buffer.count)
        _ = buffer.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
        return self._send(_buffer: buf)
    }
    private func _send(_buffer:[uint8]) -> Int {
        var buffer = _buffer
        if buffer.count==0 {
            return -1
        }
        if 0 != self.stream {
            if !self.snd_queue.isEmpty {
                var old = self.snd_queue.last!
                if old.data.count < self.mss {
                    let capacity = self.mss - uint32(old.data.count)
                    let extend = min(buffer.count, Int(capacity))
                    var seg = IKCPSEG(size: Int(old.data.count + extend))
                    self.snd_queue.append(seg)
                    
                    for i in 0..<old.data.count {
                        seg.data[i] = old.data[i]
                    }
                    
                    if 0 != buffer.count {
                        for i in 0..<extend {
                            seg.data[i+old.data.count] = buffer[i]
                            buffer = Array(UnsafeBufferPointer(start: UnsafeMutablePointer(mutating:buffer) + min(buffer.count,extend),
                                                               count: max(0, buffer.count - extend)))
                        }
                    }
                    
                    seg.frg = 0
                }
            }
            
            if buffer.count <= 0 {
                return 0
            }
        }
        var count = Int(0)
        if buffer.count <= self.mss {
            count = 1
        } else {
            count = Int((buffer.count + Int(self.mss) - 1) / Int(self.mss))
        }
        
        if count >= IKCP_WND_RCV {
            return -2
        }
        
        if 0 == count {
            count = 1
        }
        
        for i in 0..<count {
            let size = min(Int(self.mss), buffer.count)
            var seg = IKCPSEG(size: size)
            if 0 != buffer.count {
                for i in 0..<size {
                    seg.data[i] = buffer[i]
                }
            }
            
            seg.frg = (self.stream == 0) ? uint32(count - i - 1) : 0
            self.snd_queue.append(seg)
            buffer = Array(UnsafeBufferPointer(start: UnsafeMutablePointer(mutating:buffer) + min(buffer.count,size),
                                               count: max(0, buffer.count - size)))
        }
        
        return 0
    }
    
    private func updateAck(rtt:Int32) {
        var rto = uint32(0)
        if 0 == self.rx_srtt {
            self.rx_srtt = uint32(rtt)
            self.rx_rttval = uint32(rtt / 2)
        } else {
            var delta = rtt - Int32(self.rx_srtt)
            if delta < 0 {
                delta = -delta
            }
            self.rx_rttval = (3*self.rx_rttval+uint32(delta)) / 4
            self.rx_srtt = (7*self.rx_srtt+uint32(rtt)) / 8
            self.rx_srtt = max(1, self.rx_srtt)
        }
        
        rto = self.rx_srtt + max(self.interval, 4*self.rx_rttval)
        self.rx_rto = _ibound_(lower: self.rx_minrto, middle: rto, upper: IKCP_RTO_MAX)
    }
    
    private func shrinkBuf() {
        if self.snd_buf.count != 0 {
            let seg = self.snd_buf.first!
            self.snd_una = seg.sn
        } else {
            self.snd_una = self.snd_nxt
        }
    }
    
    private func parseAck(sn:uint32) {
        if timeDiff(later: sn, earlier: self.snd_una) < 0 ||
           timeDiff(later: sn, earlier: self.snd_nxt) >= 0 {
            return
        }
        let indexSet = NSMutableIndexSet()
        for i in 0..<self.snd_buf.count {
            let seg = self.snd_buf[i]
            if sn == seg.sn {
                indexSet.add(i)
            }
            
            if timeDiff(later: sn, earlier: seg.sn) < 0 {
                break
            }
        }
        
        self.snd_buf.removeAtIndexes(indexes: indexSet)
    }
    
    private func parseUna(una:uint32) {
        let indexSet = NSMutableIndexSet()
        for i in 0..<self.snd_buf.count {
            let seg = self.snd_buf[i]
            if timeDiff(later: una, earlier: seg.sn) > 0 {
                indexSet.add(i)
            } else {
                break
            }
        }
        self.snd_buf.removeAtIndexes(indexes: indexSet)
    }
    
    private func parseFastack(sn:uint32) {
        if timeDiff(later: sn, earlier: self.snd_una) < 0 ||
           timeDiff(later: sn, earlier: self.snd_nxt) >= 0 {
            return
        }
        for i in 0..<self.snd_buf.count {
            var seg = self.snd_buf[i]
            if timeDiff(later: sn, earlier: seg.sn) < 0 {
                break
            } else if (sn != seg.sn) {
                seg.fastack += 1
            }
        }
        return
    }
    
    private func ackPush(sn:uint32,ts:uint32) {
        let newsize = self.ackcount + 1
        if newsize > self.ackblock {
            var newblock = uint32(8)
            while newblock < newsize {
                newblock <<= 1
            }
            var acklist = Array<uint32>(repeating: 0, count: Int(newblock*2))
            if self.acklist.count != 0 {
                for x in 0..<Int(self.ackcount) {
                    acklist[x*2] = self.acklist[x*2]
                    acklist[x*2+1] = self.acklist[x*2+1]
                }
            }
            
            self.acklist = acklist
            self.ackblock = newblock
        }
        
        self.acklist[Int(self.ackcount * 2)] = sn
        self.acklist[Int(self.ackcount * 2 + 1)] = ts
        self.ackcount += 1
    }
    
    func wndUnused() -> Int {
        if self.rcv_queue.count < self.rcv_wnd {
            return Int(self.rcv_wnd) - self.rcv_queue.count
        }
        
        return 0;
    }
    
    private func ackGet(p:Int,sn:UnsafeMutablePointer<uint32>?,ts:UnsafeMutablePointer<uint32>?) {
        sn?.pointee = self.acklist[p*2+0]
        ts?.pointee = self.acklist[p*2+1]
    }
    func parseData(newseg:IKCPSEG) {
        let sn = newseg.sn
        var flag = false
        if timeDiff(later: sn, earlier: self.rcv_nxt + self.rcv_wnd) >= 0 || timeDiff(later: sn, earlier: self.rcv_nxt) < 0 {
            return
        }
        
        for seg in self.rcv_buf {
            if seg.sn == sn {
                flag = true
                break
            }
            if timeDiff(later: sn, earlier: seg.sn) > 0 {
                break
            }
        }
        
        if !flag {
            self.rcv_buf.append(newseg)
        }
        
        while 0 != self.rcv_buf.count {
            let seg = self.rcv_buf.first!
            if seg.sn == self.rcv_nxt && self.rcv_queue.count < self.rcv_wnd {
                self.rcv_buf.remove(at: 0)
                self.rcv_queue.append(seg)
                self.rcv_nxt += 1
            } else {
                break
            }
        }
    }
   
    func input(data:Data) -> Int {
        let buf = [uint8](repeating: 0, count: data.count)
        _ = data.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
        return self._input(dt: buf)
    }
    private func _input(dt:[uint8]) -> Int {
        var data = dt
        let una = self.snd_una
        var maxack = uint32(0)
        var flag = false
        if self.canlog(mask: IKCP_LOG_OUTPUT) {
            self.log(mask: IKCP_LOG_OUTPUT, fmt: "[RI] %d bytes", data.count)
        }
        
        if data.count<IKCP_OVERHEAD {
            return -1
        }
        
        while (true) {
            var ts = uint32(0),sn = uint32(0), len = uint32(0),una = uint32(0),conv = uint32(0)
            var wnd = uint16(0)
            var cmd = uint8(0),frg = uint8(0)
            if data.count < Int(IKCP_OVERHEAD) {
                break
            }
            
//            let dataSize = data.count
            data = Array(UnsafeBufferPointer(start: KCPDecode32u(p: UnsafeMutablePointer(mutating:data), l: &conv), count: max(0, data.count - 4)))
            if conv != self.conv {
                return -1
            }
            data = Array(UnsafeBufferPointer(start: KCPDecode8u(p: UnsafeMutablePointer(mutating:data),
                                                                c: &cmd),
                                             count: max(0, data.count - 1)))
            data = Array(UnsafeBufferPointer(start: KCPDecode8u(p: UnsafeMutablePointer(mutating:data),
                                                                c: &frg),
                                             count: max(0, data.count - 1)))
            data = Array(UnsafeBufferPointer(start: KCPDecode16u(p: UnsafeMutablePointer(mutating:data),
                                                                 w: &wnd),
                                             count: max(0, data.count - 2)))
            data = Array(UnsafeBufferPointer(start: KCPDecode32u(p: UnsafeMutablePointer(mutating:data),
                                                                 l: &ts),
                                             count: max(0, data.count - 4)))
            data = Array(UnsafeBufferPointer(start: KCPDecode32u(p: UnsafeMutablePointer(mutating:data),
                                                                 l: &sn),
                                             count: max(0, data.count - 4)))
            data = Array(UnsafeBufferPointer(start: KCPDecode32u(p: UnsafeMutablePointer(mutating:data),
                                                                 l: &una),
                                             count: max(0, data.count - 4)))
            data = Array(UnsafeBufferPointer(start: KCPDecode32u(p: UnsafeMutablePointer(mutating:data),
                                                                 l: &len),
                                             count: max(0, data.count - 4)))
            
            if data.count < len {
                return -2
            }
           
            if IKCP_CMD_PUSH != cmd && IKCP_CMD_ACK != cmd &&
                IKCP_CMD_WASK != cmd && IKCP_CMD_WINS != cmd {
                return -3
            }
            
            self.rmt_wnd = uint32(wnd);
            self.parseUna(una: una)
            self.shrinkBuf()
            if IKCP_CMD_ACK == cmd {
                if timeDiff(later: self.current, earlier: ts) >= 0 {
                    self.updateAck(rtt: timeDiff(later: self.current, earlier: ts))
                }
                self.parseAck(sn: sn)
                self.shrinkBuf()
                if !flag {
                    flag = true
                    maxack = sn
                } else {
                    if timeDiff(later: sn, earlier: maxack) > 0 {
                        maxack = sn
                    }
                }
                
                if self.canlog(mask: IKCP_LOG_IN_ACK) {
                    self.log(mask: IKCP_LOG_IN_ACK,
                             fmt: "input ack: sn=%lu rtt=%@ rto=%@",
                             sn,timeDiff(later: self.current, earlier: ts),self.rx_rto)
                }
            } else if IKCP_CMD_PUSH == cmd {
                if self.canlog(mask: IKCP_LOG_IN_DATA) {
                    self.log(mask: IKCP_LOG_IN_DATA,fmt: "input psh: sn=%@ ts=%@", sn,ts)
                }
                
                if timeDiff(later: sn, earlier: self.rcv_nxt + self.rcv_wnd) < 0 {
                   self.ackPush(sn: sn, ts: ts)
                    if timeDiff(later: sn, earlier: self.rcv_nxt) >= 0 {
                        var seg = IKCPSEG(size: Int(len))
                        seg.conv = conv
                        seg.cmd = uint32(cmd)
                        seg.frg = uint32(frg)
                        seg.wnd = uint32(wnd)
                        seg.ts = ts
                        seg.sn = sn
                        seg.una = una
                        if len > 0 {
                            for i in 0..<seg.data.count {
                                seg.data[i] = data[i]
                            }
                        }
                        
                        self.parseData(newseg: seg)
                    }
                }
            } else if IKCP_CMD_WASK == cmd {
                self.probe |= IKCP_ASK_TELL
                if self.canlog(mask: IKCP_LOG_IN_PROBE) {
                    self.log(mask: IKCP_LOG_IN_PROBE, fmt: "input probe")
                }
            } else if IKCP_CMD_WINS == cmd {
                if self.canlog(mask: IKCP_LOG_IN_WINS) {
                    self.log(mask: IKCP_LOG_IN_WINS, fmt: "input wins: %lu",uint32(wnd))
                }
            } else {
                return -3
            }
            
            data = Array(UnsafeBufferPointer(start: UnsafeMutablePointer(mutating:data) + Int(len),
                                             count: max(0, data.count - Int(len))))
        }
        
        if flag {
            self.parseFastack(sn: maxack)
        }
        
        if timeDiff(later: self.snd_una, earlier: una) > 0 {
            if self.cwnd < self.rmt_wnd {
                let mss = self.mss
                if self.cwnd < self.ssthresh {
                    self.cwnd += 1
                    self.incr += mss
                } else {
                    if self.incr < mss {
                        self.incr = mss
                    }
                    self.incr += (mss*mss) / self.incr + (mss / 16)
                    if (self.cwnd + 1) * mss <= self.incr {
                        self.cwnd += 1
                    }
                }
                
                if self.cwnd > self.rmt_wnd {
                    self.cwnd = self.rmt_wnd
                    self.incr = self.rmt_wnd * mss
                }
            }
        }
        return 0
    }
    
    func flush() {
        let current = self.current
        let buffer = UnsafeMutablePointer(mutating: self.buffer)
        var ptr =  UnsafeMutablePointer(mutating: self.buffer)
        if self.updated == 0 {
            return
        }
        
        var seg = IKCPSEG()
        seg.conv = self.conv
        seg.cmd = IKCP_CMD_ACK
        seg.frg = 0
        seg.wnd = uint32(self.wndUnused())
        seg.una = self.rcv_nxt
        seg.sn = 0
        seg.ts = 0
        
        for i in 0..<Int(self.ackcount) {
            let size = uint32(ptr - buffer)
            if size + IKCP_OVERHEAD > self.mtu {
                let data = Array(UnsafeBufferPointer(start: buffer,
                                                     count: Int(size)))
                _ = self._output(data: data)
                ptr = buffer
            }
            
            self.ackGet(p: i, sn: &seg.sn, ts: &seg.ts)
            let data : Data = seg.encode()
            let buf = [uint8](repeating: 0, count: data.count)
            _ = data.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
            for b in buf {
                ptr.pointee = b
                ptr += 1
            }
        }
//        self.acklist.removeAll()
        self.ackcount = 0
        
        if 0 == self.rmt_wnd {
            if 0 == self.probe_wait {
                self.probe_wait = IKCP_PROBE_INIT
                self.ts_probe = self.current + self.probe_wait
            } else {
                if timeDiff(later: self.current, earlier: self.ts_probe) >= 0 {
                    if self.probe_wait < IKCP_PROBE_INIT {
                        self.probe_wait = IKCP_PROBE_INIT
                    }
                    self.probe_wait += self.probe_wait / 2
                    if self.probe_wait > IKCP_PROBE_LIMIT {
                        self.probe_wait = IKCP_PROBE_LIMIT
                    }
                    self.ts_probe = self.current + self.probe_wait
                    self.probe |= IKCP_ASK_SEND
                }
            }
        } else {
            self.ts_probe = 0
            self.probe_wait = 0
        }
        
        if 0 != (self.probe & IKCP_ASK_SEND) {
            seg.cmd = IKCP_CMD_WASK
            let size = uint32(ptr - buffer)
            if size + IKCP_OVERHEAD > self.mtu {
                let data = Array(UnsafeBufferPointer(start: buffer,
                                                     count: Int(size)))
                _ = self._output(data: data)
                ptr = buffer
            }
            
            let data : Data = seg.encode()
            let buf = [uint8](repeating: 0, count: data.count)
            _ = data.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
            for b in buf {
                ptr.pointee = b
                ptr += 1
            }
        }
        
        if 0 != (self.probe & IKCP_ASK_TELL) {
            seg.cmd = IKCP_CMD_WINS
            let size = uint32(ptr - buffer)
            if size + IKCP_OVERHEAD > self.mtu {
                let data = Array(UnsafeBufferPointer(start: buffer,
                                                     count: Int(size)))
                _ = self._output(data: data)
                ptr = buffer
            }
            let data : Data = seg.encode()
            let buf = [uint8](repeating: 0, count: data.count)
            _ = data.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
            for b in buf {
                ptr.pointee = b
                ptr += 1
            }
        }
        
        self.probe = 0
        
        var cwnd = min(self.snd_wnd, self.rmt_wnd)
        if 0 == self.nocwnd {
            cwnd = min(self.cwnd, cwnd)
        }
        
        while timeDiff(later: self.snd_nxt, earlier: self.snd_una + cwnd) < 0 {
            if self.snd_queue.isEmpty {
                break
            }
            
            var newseg = self.snd_queue.first!
            self.snd_queue.remove(at: 0)

            newseg.conv = self.conv
            newseg.cmd = IKCP_CMD_PUSH
            newseg.wnd = seg.wnd
            newseg.ts = current
            newseg.sn = self.snd_nxt; self.snd_nxt+=1;
            newseg.una = self.rcv_nxt
            newseg.resendts = current
            newseg.rto = self.rx_rto
            newseg.fastack = 0
            newseg.xmit = 0
            
            self.snd_buf.append(newseg)
        }
        
        let resent = self.fastresend > 0 ? self.fastresend : 0xffffffff
        let rtomin = (0 == self.nodelay) ? (self.rx_rto >> 3) : 0
        var lost = false
        var change = Int(0)
        
        for var segment in self.snd_buf {
            var needsend = false
            if 0 == segment.xmit {
                needsend = true
                segment.xmit += 1
                segment.rto = self.rx_rto
                segment.resendts = current + segment.rto + rtomin
            } else if timeDiff(later: current, earlier: segment.resendts) >= 0{
                needsend = true
                segment.xmit += 1
                self.xmit += 1
                if 0 == self.nodelay {
                    segment.rto += self.rx_rto
                } else {
                    segment.rto += self.rx_rto / 2
                }
                segment.resendts = current + segment.rto
                lost = true
            } else if segment.fastack >= resent {
                needsend = true
                segment.xmit += 1
                segment.fastack = 0
                segment.resendts = current + segment.rto
                change += 1
            }
            
            if needsend {
                segment.ts = current
                segment.wnd = seg.wnd
                segment.una = self.rcv_nxt
                
                let size = Int(ptr - buffer)
                let need = Int(IKCP_OVERHEAD) + segment.data.count
                
                if size + need > self.mtu {
                    _ = self._output(data: Array(UnsafeBufferPointer(start: buffer,
                                                                         count: size)))
                    ptr = buffer
                }
                
                let data : Data = segment.encode()
                let buf = [uint8](repeating: 0, count: data.count)
                _ = data.copyBytes(to: UnsafeMutableBufferPointer<uint8>(start: UnsafeMutablePointer(mutating: buf), count: buf.count))
                for b in buf {
                    ptr.pointee = b
                    ptr += 1
                }
                
                if segment.data.count > 0 {
                    for i in 0..<segment.data.count {
                        ptr.pointee = segment.data[Int(i)]
                        ptr += 1
                    }
                }
                
                if segment.xmit >= self.dead_link {
                    self.state = uint32(-1)
                }
            }
        }
        
        let size = Int(ptr - buffer)
        if size > 0 {
            _ = self._output(data: Array(UnsafeBufferPointer(start: buffer,
                                                                 count: size)))
        }
        
        if 0 != change {
            let inflight = self.snd_nxt - self.snd_una
            self.ssthresh = inflight / 2
            if self.ssthresh < IKCP_THRESH_MIN {
                self.ssthresh = IKCP_THRESH_MIN
            }
            self.cwnd = self.ssthresh + uint32(resent)
            self.incr = self.cwnd * self.mss
        }
        
        if lost {
            self.ssthresh = cwnd / 2
            if self.ssthresh < IKCP_THRESH_MIN {
                self.ssthresh = IKCP_THRESH_MIN
            }
            self.cwnd = 1
            self.incr = self.mss
        }
        
        if self.cwnd < 1 {
            self.cwnd = 1
            self.incr = self.mss
        }
    }
    
    func update(current:uint32) {
        var slap = Int32(0)
        self.current = current
        if 0 == self.updated {
            self.updated = 1
            self.ts_flush = self.current
        }
        slap = timeDiff(later: self.current, earlier: self.ts_flush)
        if slap >= 10000 || slap < -10000 {
            self.ts_flush = self.current
            slap = 0
        }
        
        if slap >= 0 {
            self.ts_flush += self.interval
            if timeDiff(later: self.current, earlier: self.ts_flush) >= 0 {
                self.ts_flush = self.current + self.interval
            }
            self.flush()
        }
    }
    
    func check(current:uint32) -> uint32 {
        var ts_flush = self.ts_flush
        var tm_flush = Int32(0x7fffffff)
        var tm_packet = Int32(0x7fffffff)
        var minimal = uint32(0)
        
        if 0 == self.updated {
            return current
        }
        
        if timeDiff(later: current,earlier: ts_flush) >= 10000 ||
            timeDiff(later: current,earlier: ts_flush) < -10000 {
            ts_flush = current
        }
       
        if timeDiff(later: current,earlier: ts_flush) >= 0 {
            return current
        }
        
        tm_flush = timeDiff(later: ts_flush,earlier: current)
        for seg in self.snd_buf {
            let diff = timeDiff(later: seg.resendts, earlier: current)
            if diff <= 0 {
                return current
            }
            
            if diff < tm_packet {
                tm_packet = diff
            }
        }
        
        minimal = uint32(tm_packet < tm_flush ? tm_packet : tm_flush)
        if minimal > self.interval {
            minimal = self.interval
        }
        return current + minimal
    }
    
    func setmtu(mtu:uint32) -> Int {
        if self.mtu < 50 || mtu < IKCP_OVERHEAD {
            return -1
        }
        let buffer = [uint8](repeating: 0, count: Int((mtu + IKCP_OVERHEAD)*3))
        self.mtu = mtu
        self.mss = self.mtu - IKCP_OVERHEAD
        self.buffer = buffer
        return 0
    }
    
    func `internal`(internalVal:uint32) -> Int {
        var val = internalVal
        if val > 5000 {
            val = 5000
        } else if val < 10 {
            val = 10
        }
        self.interval = val
        return 0;
    }
    
    func nodelay(nodelay:uint32,internalVal:uint32,resend:uint32,nc:uint32) -> Int {
        if nodelay >= 0 {
            self.nodelay = nodelay
            if 0 != nodelay {
                self.rx_minrto = IKCP_RTO_NDL
            } else {
                self.rx_minrto = IKCP_RTO_MIN
            }
        }
        
        if 0 <= internalVal {
            var internalValue = internalVal
            if internalValue > 5000 {
                internalValue = 5000
            } else if (internalValue < 10) {
                internalValue = 10
            }
            self.interval = internalValue
        }
        if resend >= 0 {
            self.fastresend = Int(resend)
        }
        
        if nc >= 0 {
            self.nocwnd = Int(nc)
        }
        return 0
    }
    
    func wndSize(sndwnd:uint32,rcvwnd:uint32) -> Int {
        if sndwnd > 0 {
            self.snd_wnd = sndwnd
        }
        if rcvwnd > 0 {
            self.rcv_wnd = max(rcvwnd, IKCP_WND_RCV)
        }
        return 0;
    }
    
    func waitsnd() -> Int {
        return self.snd_buf.count+self.snd_queue.count
    }
   
    func canlog(mask:Int) -> Bool {
        if 0==(mask&self.logmask) || nil == self.writelog {
            return false
        }
        
        return true
    }
    
    func log(mask:Int,fmt:String, _ args: CVarArg...) {
        if 0 == mask & self.logmask || nil == self.writelog {
            return
        }
        
        let log = String.localizedStringWithFormat(fmt, args)
        var weakSelf = self
        self.writelog?(log,&weakSelf,self.user)
    }
    
    private func _output(data:[uint8]) -> Int {
        if nil == self.output {
            return 0
        }
        if self.canlog(mask: IKCP_LOG_OUTPUT) {
            self.log(mask: IKCP_LOG_OUTPUT, fmt: "[RO] %@ bytes", data.count)
        }
        
        if 0 == data.count {
            return 0
        }
        var weakSelf = self
        let ret = self.output?(data,&weakSelf,self.user)
        if nil==ret {
            return 0;
        }
        return ret!
    }
}

func getConv(ptr:UnsafeMutablePointer<uint8>) -> UInt32 {
    var conv = UInt32(0)
    _ = KCPDecode32u(p: ptr, l: &conv)
    return conv
}
