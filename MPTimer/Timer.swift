//
//  Timer.swift
//  MPTimer
//
//  Created by Matias Piipari on 15/04/2016.
//  Copyright © 2016 Manuscripts.app Limited. All rights reserved.
//

import Foundation
import MachO
import ObjectiveC

public enum TimerBehavior {
    case coalesce
    case delay
}

public typealias ObjCCompatibleDoBlock = @convention(block) (AnyObject) -> Void
public typealias LockedBlock = @convention(block) () -> Void

public final class Timer<TimedObject:AnyObject>:NSObject {
    
    private lazy var __once: () = {
        mach_timebase_info(&self.machTimeInfo)
    }()
    
    fileprivate weak var object:TimedObject?
    fileprivate let behavior:TimerBehavior
    
    fileprivate let queue:DispatchQueue
    fileprivate var timer:DispatchSourceTimer?
    fileprivate var nextFireTime:TimeInterval?
    
    public init(object:TimedObject, behavior:TimerBehavior = .coalesce, queueLabel:String = "com.manuscriptsapp.Timer") {
        self.object = object
        self.behavior = behavior
        self.queue = DispatchQueue(label: queueLabel, attributes: [])
    }
    
    fileprivate func _cancel() {
        guard let scheduledTimer = timer else {
            return
        }
        
        scheduledTimer.cancel()
        self.timer = nil
    }
    
    public func cancel() {
        self.whileLocked {
            self._cancel()
        }
    }
    
    deinit {
        self._cancel()
    }
    
    public func setTargetQueue(_ target:DispatchQueue) {
        self.queue.setTarget(queue: target)
    }
        
    fileprivate var machTimeOnceToken:Int = 0
    fileprivate var machTimeInfo = mach_timebase_info_data_t()
    fileprivate func timeInfo() -> mach_timebase_info_data_t {
        _ = self.__once
        return machTimeInfo
    }
    
    fileprivate func now() -> TimeInterval {
        var t:TimeInterval = TimeInterval(mach_absolute_time())
        let timeInfo = self.timeInfo()
        t *= TimeInterval(timeInfo.numer)
        t /= TimeInterval(timeInfo.denom)
        return t / Double(NSEC_PER_SEC)
    }
    
    public func whileLocked(perform block:LockedBlock) {
        self.queue.sync(execute: block)
    }
    
    public func after(delay:TimeInterval, perform block:@escaping (TimedObject)->Void) {
        let doBlock:ObjCCompatibleDoBlock = { obj in
            block(obj as! TimedObject)
        }
        self.after(delay: delay, perform:doBlock)
    }
    
    public func after(delay:TimeInterval, perform block:@escaping ObjCCompatibleDoBlock) {
        let requestTime = now()
        
        self.whileLocked {
            
            // adjust delay to take into account time elapsed between the method call and execution of this block
            let nowValue = self.now()
            
            var adjustedDelay:TimeInterval = delay - (nowValue - requestTime)
            if (adjustedDelay < 0.0) {
                adjustedDelay = 0.0
            }
            
            let hasTimer:Bool = self.timer != nil
            let shouldProceed:Bool

            if !hasTimer {
                shouldProceed = true
            }
            else if self.behavior == .delay {
                shouldProceed = true
            }
            else if self.behavior == .coalesce, let nextFireTime = self.nextFireTime, (self.now() + adjustedDelay) < nextFireTime {
                shouldProceed = true
            }
            else {
                shouldProceed = false
            }
            
            guard shouldProceed else {
                return
            }
            
            if !hasTimer {
                self.timer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: 0),
                                                            queue: self.queue)
            }
            
            guard let timer = self.timer else {
                preconditionFailure("Timer should always be initialized in this code path.")
            }
            
            let td = Int64(ceil(Double(adjustedDelay) * Double(NSEC_PER_SEC)))
            let t = DispatchTime.now() + Double(td) / Double(NSEC_PER_SEC)
            
            timer.scheduleOneshot(deadline: t)
            
            self.nextFireTime = self.now() + adjustedDelay

            timer.setEventHandler {
                if let object = self.object {
                    block(object) // nothing is done if object was meanwhile set to nil
                }
                self._cancel()
            }
            
            // if the timer was newly created.
            if !hasTimer {
                timer.resume()
            }
        }
    }
}
