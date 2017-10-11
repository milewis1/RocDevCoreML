//
//  TouchCanvas.swift
//  HandwritingDemo
//
//  Created by Michael Lewis-Swanson on 10/3/17.
//  Copyright © 2017 Michael Lewis-Swanson. All rights reserved.
//
import UIKit


class TouchCanvas: UIImageView {
    private var location: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        image = UIImage()
        
        let touch = touches.first
        location = touch?.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first
        let currentLocation = touch?.location(in: self)

        drawLine(currentLocation!)

        location = currentLocation
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first
        let currentLocation = touch?.location(in: self)

        drawLine(currentLocation!)

        location = currentLocation
    }

    private func drawLine(_ currentLocation: CGPoint) {

        UIGraphicsBeginImageContext(frame.size)
        if let ctx = UIGraphicsGetCurrentContext() {

            image!.draw(in: CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height))
            ctx.setLineCap(.round)
            ctx.setLineWidth(8.0)
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: location?.x ?? 0, y: location?.y ?? 0))
            ctx.addLine(to: CGPoint(x: currentLocation.x, y: currentLocation.y))
            ctx.strokePath()

            self.image = UIGraphicsGetImageFromCurrentImageContext()
        }
        UIGraphicsEndImageContext()

    }

}
