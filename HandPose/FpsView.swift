//
//  FpsView.swift
//  HandPose
//
//  Created by Reece Dantin on 8/13/20.
//  Copyright © 2020 Apple. All rights reserved.
//

import UIKit
import AVFoundation

class FpsView: UIView {

    private var overlayLayer = CAShapeLayer()
    private var fpsPath = UIBezierPath()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupOverlay()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlay()
    }
    

    private func setupOverlay() {
        self.layer.addSublayer(overlayLayer)
        overlayLayer.opacity = 0.5
        overlayLayer.lineWidth = 2
        overlayLayer.lineJoin = CAShapeLayerLineJoin.miter
        overlayLayer.strokeColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor
        overlayLayer.fillColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor
    }
    
    func showPoints(_ points: [Int]) {
        fpsPath.removeAllPoints()
        fpsPath.move(to: CGPoint(x: 0, y: CGFloat(self.frame.height)))
        var countPoints = 0

        for fpspoint in points {
            let pointx = Float(countPoints) / Float(points.count - 1)
            let pointy = Double(60 - fpspoint) / 60.0

            countPoints += 1
            let point = CGPoint(x: CGFloat(pointx) * CGFloat(self.frame.width), y: CGFloat(pointy) * CGFloat(self.frame.height))
            fpsPath.addLine(to: point)
        }
        fpsPath.addLine(to: CGPoint(x: CGFloat(self.frame.width), y: CGFloat(self.frame.height)))
        
        overlayLayer.fillColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor
        overlayLayer.path = fpsPath.cgPath
    }
}
