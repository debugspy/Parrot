import Cocoa

/* TODO: Support window key-ness: -_windowChangedKeyState. */

/// adapted from from @Tueno: https://github.com/Tueno/MessageProgressView
public class MessageProgressView: NSView {
    
    public var diameter: CGFloat = 8 {
        didSet {
            self.needsDisplay = true
        }
    }
    
    public var margin: CGFloat = 6 {
        didSet {
            self.needsDisplay = true
        }
    }
    
    public var numberOfDots: Int = 3 {
        didSet {
            self.needsDisplay = true
        }
    }
    
    public var dotColor: NSColor = NSColor.selectedMenuItemColor {
        didSet {
            self.needsDisplay = true
        }
    }
    
    private var progressLayer: MessageProgressLayer!
    
    //
    //
    //
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer!.backgroundColor = .ns(.clear)
        self.layer!.masksToBounds = false
        
        self.updateLayer() // bootstrapping
    }
    
    //
    //
    //
    
    public override var acceptsFirstResponder: Bool {
        return false
    }
    
    private func layerFrame() -> NSRect {
        var layerFrame = CGRect.zero
        let w = CGFloat(self.numberOfDots) * (self.diameter + self.margin) + self.margin
        layerFrame.size = NSSize(width: w, height: self.diameter)
        return layerFrame
    }
    
    public override var intrinsicContentSize: NSSize {
        let r = self.layerFrame()
        return NSSize(width: r.size.width, height: r.size.height * 2)
    }
    
    //
    //
    //
    
    public override var allowsVibrancy: Bool { return true }
    public override var wantsUpdateLayer: Bool { return true }
    public override func updateLayer() {
        let animating = self.progressLayer?.animating ?? false
        self.progressLayer?.stopAnimation()
        self.progressLayer?.removeFromSuperlayer()
        
        // We need to recreate the whole thing because the dot initialization is rough.
        self.progressLayer = MessageProgressLayer(diameter: self.diameter, margin: self.margin,
                                                  numberOfDots: self.numberOfDots, dotColor: self.dotColor)
        self.layer!.addSublayer(self.progressLayer)
        
        // The position should be adjusted half a height up to account for the anim.
        self.progressLayer.frame = self.layerFrame()
        var pt = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        pt.y += self.progressLayer.frame.height / 2
        self.progressLayer.position = pt
        
        // Resume if we were animating.
        if animating {
            self.progressLayer.startAnimation()
        }
    }
    
    //
    //
    //
    
    public func startAnimation() {
        self.progressLayer.startAnimation()
    }
    
    public func stopAnimation() {
        self.progressLayer.stopAnimation()
    }
}

fileprivate class MessageProgressLayer: CALayer {
    
    fileprivate let diameter: CGFloat
    fileprivate let margin: CGFloat
    fileprivate let numberOfDots: Int
    fileprivate let dotColor: NSColor
    fileprivate let bounceDuration: Double = 0.3
    
    fileprivate var animating = false
    fileprivate var circleShapeLayers: [CAShapeLayer] = []
    
    //
    //
    //
    
    fileprivate init(diameter: CGFloat, margin: CGFloat, numberOfDots: Int, dotColor: NSColor) {
        self.diameter = diameter
        self.margin = margin
        self.numberOfDots = numberOfDots
        self.dotColor = dotColor
        
        super.init()
        initShapeLayers()
    }
    fileprivate required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func initShapeLayers() {
        for i in stride(from: 0, to: numberOfDots, by: 1) {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).cgPath
            shapeLayer.fillColor = dotColor.cgColor
            shapeLayer.position = CGPoint(x: CGFloat(i) * (diameter + margin) + margin, y: 0)
            addSublayer(shapeLayer)
            self.circleShapeLayers.append(shapeLayer)
        }
    }
    
    //
    //
    //
    
    fileprivate func startAnimation() {
        guard !self.animating else { return }
        let group = CAAnimationGroup()
        group.repeatCount = Float.infinity
        group.duration = self.bounceDuration * 3
        let yTranslation = CABasicAnimation(keyPath: "transform.translation.y")
        yTranslation.fromValue = 0
        yTranslation.toValue = self.diameter * -1
        yTranslation.duration = self.bounceDuration
        yTranslation.isRemovedOnCompletion = false
        yTranslation.autoreverses = true
        
        for i in stride(from: 0, to: circleShapeLayers.count, by: 1) {
            let layer = self.circleShapeLayers[i]
            group.beginTime = CACurrentMediaTime() + Double(i) * yTranslation.duration * 0.5
            group.animations = [yTranslation]
            layer.add(group, forKey: "jump")
        }
        self.animating = true
    }
    
    fileprivate func stopAnimation() {
        guard self.animating else { return }
        for i in stride(from: 0, to: circleShapeLayers.count, by: 1) {
            let layer = circleShapeLayers[i]
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
        }
        self.animating = false
    }
}

public extension NSBezierPath {
    
    public var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0 ..< self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveToBezierPathElement: path.move(to: points[0])
            case .lineToBezierPathElement: path.addLine(to: points[0])
            case .curveToBezierPathElement: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePathBezierPathElement: path.closeSubpath()
            }
        }
        return path
    }
}
