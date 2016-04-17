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
    case Coalesce
    case Delay
}

public typealias DoBlock = @convention(block) (object:AnyObject) -> Void
public typealias LockedBlock = @convention(block) () -> Void

public class Timer:NSObject {
    private weak var object:AnyObject?
    
    private let queue:dispatch_queue_t
    private var timer:dispatch_source_t?
    private let behavior:TimerBehavior
    private var nextFireTime:NSTimeInterval?
    
    public convenience init(object:AnyObject) {
        self.init(object:object, behavior:.Coalesce, queueLabel: "com.manuscriptsapp.Timer")
    }

    public required init(object:AnyObject, behavior:TimerBehavior, queueLabel:String) {
        self.object = object
        self.behavior = behavior
        self.queue = dispatch_queue_create(queueLabel, DISPATCH_QUEUE_SERIAL)
    }
    
    public func _cancel() {
        guard let scheduledTimer = timer else {
            return
        }
        
        dispatch_source_cancel(scheduledTimer)
        self.timer = nil
    }
    
    func cancel() {
        self.whileLocked {
            self._cancel()
        }
    }
    
    deinit {
        self._cancel()
    }
    
    public func setTargetQueue(target:dispatch_queue_t) {
        dispatch_set_target_queue(self.queue, target)
    }
        
    private static var pred:dispatch_once_t = 0
    private static var machTimeInfo = mach_timebase_info_data_t()

    static func timeInfo() -> mach_timebase_info_data_t {
        dispatch_once(&pred) {
            mach_timebase_info(&machTimeInfo)
        }
        return machTimeInfo
    }
    
    func now() -> NSTimeInterval {
        var t:NSTimeInterval = NSTimeInterval(mach_absolute_time())
        let timeInfo = self.dynamicType.timeInfo()
        t *= NSTimeInterval(timeInfo.numer)
        t /= NSTimeInterval(timeInfo.denom)
        return t / Double(NSEC_PER_SEC)
    }
    
    public func whileLocked(perform block:LockedBlock) {
        dispatch_sync(self.queue, block)
    }
    
    func after(delay delay:NSTimeInterval, perform block:DoBlock) {
        let requestTime = now()
        
        self.whileLocked {
            
            // adjust delay to take into account time elapsed between the method call and execution of this block
            let nowValue = self.now()
            
            var adjustedDelay:NSTimeInterval = delay - (nowValue - requestTime)
            if (adjustedDelay < 0.0) {
                adjustedDelay = 0.0
            }
            
            let hasTimer:Bool = self.timer != nil
            let shouldProceed:Bool

            if !hasTimer {
                shouldProceed = true
            }
            else if self.behavior == .Delay {
                shouldProceed = true
            }
            else if self.behavior == .Coalesce && (self.nextFireTime != nil || (self.now() + adjustedDelay) < self.nextFireTime) {
                shouldProceed = true
            }
            else {
                shouldProceed = false
            }
            
            guard shouldProceed else {
                return
            }
            
            if !hasTimer {
                self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue)
            }
            
            guard let timer = self.timer else {
                preconditionFailure("Timer should always be initialized in this code path.")
            }
            
            let td = Int64(ceil(Double(adjustedDelay) * Double(NSEC_PER_SEC)))
            let t = dispatch_time(DISPATCH_TIME_NOW, td)
            
            dispatch_source_set_timer(timer, t, 0, 0)
            self.nextFireTime = self.now() + adjustedDelay

            dispatch_source_set_event_handler(timer) {
                if let object = self.object {
                    block(object: object) // nothing is done if object was meanwhile set to nil
                }
                self._cancel()
            }
            
            // if the timer was newly created.
            if !hasTimer {
                dispatch_resume(timer)
            }
        }
    }
}