import UIKit
import PencilKit

// Yapışkan notun açık hâli: üstte klavyeyle yazı, altında kalemle yazılabilen alan; renk seçimi, silme.
final class NotEditoru: UIViewController, UITextViewDelegate {
    private var not: YapiskanNot
    var bitti: ((YapiskanNot) -> Void)?
    var sil: (() -> Void)?
    private let yazi = UITextView()
    private let tuval = PKCanvasView()
    private let palet = PKToolPicker()
    private var renkDugmeleri: [UIButton] = []

    init(not: YapiskanNot) { self.not = not; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = NotRenk.renk(not.renk)

        let baslik = UILabel(); baslik.text = "Yapışkan not"; baslik.font = .systemFont(ofSize: 19, weight: .bold)
        baslik.textColor = UIColor(white: 0.12, alpha: 1)
        let silB = UIButton(type: .system, primaryAction: UIAction(title: "Sil", image: UIImage(systemName: "trash")) { [weak self] _ in
            guard let self else { return }
            self.bitti = nil
            self.dismiss(animated: true) { self.sil?() }
        })
        silB.tintColor = .systemRed
        var bc = UIButton.Configuration.filled(); bc.title = "Bitti"; bc.cornerStyle = .capsule; bc.baseBackgroundColor = UIColor(white: 0.12, alpha: 1)
        let bittiB = UIButton(configuration: bc, primaryAction: UIAction { [weak self] _ in self?.kapat() })
        bittiB.accessibilityIdentifier = "notBitti"

        let renkler = UIStackView(); renkler.spacing = 8
        for (ad, _) in NotRenk.secenekler {
            let b = UIButton(type: .custom, primaryAction: UIAction { [weak self] _ in self?.renkSec(ad) })
            b.backgroundColor = NotRenk.renk(ad)
            b.layer.cornerRadius = 14; b.layer.borderWidth = 2
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true; b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            b.accessibilityLabel = "Not rengi " + ad
            b.tag = renkDugmeleri.count
            renkDugmeleri.append(b); renkler.addArrangedSubview(b)
        }
        renkCerceve()

        let ust = UIStackView(arrangedSubviews: [baslik, UIView(), renkler, silB, bittiB]); ust.spacing = 14; ust.alignment = .center

        yazi.text = not.yazi
        yazi.font = .systemFont(ofSize: 19)
        yazi.backgroundColor = UIColor(white: 1, alpha: 0.35)
        yazi.layer.cornerRadius = 10
        yazi.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        yazi.delegate = self
        yazi.accessibilityIdentifier = "notYazi"

        let ipucu = UILabel(); ipucu.text = "Kalemle yazın"; ipucu.font = .systemFont(ofSize: 13, weight: .semibold); ipucu.textColor = UIColor(white: 0.1, alpha: 0.45)

        tuval.backgroundColor = UIColor(white: 1, alpha: 0.2)
        tuval.isOpaque = false
        tuval.layer.cornerRadius = 10
        tuval.drawingPolicy = Ayar.ornek ? .anyInput : .pencilOnly
        if let d = not.cizim, let c = try? PKDrawing(data: d) { tuval.drawing = c }
        tuval.tool = PKInkingTool(.pen, color: UIColor(white: 0.1, alpha: 1), width: 3)

        let yigin = UIStackView(arrangedSubviews: [ust, yazi, ipucu, tuval]); yigin.axis = .vertical; yigin.spacing = 10
        yigin.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(yigin)
        NSLayoutConstraint.activate([
            yigin.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            yigin.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            yigin.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            yigin.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            yazi.heightAnchor.constraint(equalToConstant: 110),
        ])
        palet.addObserver(tuval)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        palet.setVisible(true, forFirstResponder: tuval)
        tuval.becomeFirstResponder()
    }

    private func renkSec(_ ad: String) {
        not.renk = ad
        UIView.animate(withDuration: 0.2) { self.view.backgroundColor = NotRenk.renk(ad) }
        renkCerceve()
    }
    private func renkCerceve() {
        for (i, b) in renkDugmeleri.enumerated() {
            b.layer.borderColor = (NotRenk.secenekler[i].0 == not.renk ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0, alpha: 0.12)).cgColor
        }
    }
    private func kapat() {
        not.yazi = yazi.text ?? ""
        not.cizim = tuval.drawing.strokes.isEmpty ? nil : tuval.drawing.dataRepresentation()
        not.zaman = Zaman.simdi
        palet.setVisible(false, forFirstResponder: tuval)
        let n = not, geriCagri = bitti
        bitti = nil
        dismiss(animated: true) { geriCagri?(n) }
    }
    // Kenara dokunarak / aşağı kaydırarak kapatılırsa da kaydet
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let geriCagri = bitti else { return }
        bitti = nil
        not.yazi = yazi.text ?? ""
        not.cizim = tuval.drawing.strokes.isEmpty ? nil : tuval.drawing.dataRepresentation()
        geriCagri(not)
    }
}
