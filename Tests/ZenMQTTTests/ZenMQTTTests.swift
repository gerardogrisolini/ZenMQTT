import XCTest
import NIO
@testable import ZenMQTT

final class ZenMQTTTests: XCTestCase {
    
    var eventLoopGroup: MultiThreadedEventLoopGroup!
    
    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    override func tearDown() {
        try! eventLoopGroup.syncShutdownGracefully()
    }
    
    func testExample() {
        let mqtt = ZenMQTT(host: "biesseprodnf-gwagent.cpaas-accenture.com", port: 8883, clientID: "test_\(Date())", autoReconnect: true, eventLoopGroup: eventLoopGroup)
        XCTAssertNoThrow(try mqtt.addTLS(
            cert: "/Users/gerardo/Projects/ZenSTOMP/stunnel_client_neptune.pem.crt",
            key: "/Users/gerardo/Projects/ZenSTOMP/stunnel_client.private_neptune.pem.key"
        ))

        mqtt.onMessageReceived = { message in
            print(message.stringRepresentation!)
        }
        
        mqtt.onHandlerRemoved = {
            print("Handler removed")
        }

        mqtt.onErrorCaught = { error in
            print(error.localizedDescription)
        }
        
        
        let bigMessage = """
Dopo la conferenza stampa di presentazione del 14 gennaio 2020, Amadeus è stato accusato di sessismo in quanto, annunciando la presenza tra le donne della kermesse di Francesca Sofia Novello, modella e fidanzata di Valentino Rossi, dice di «averla scelta per la bellezza ma anche per la capacità di stare accanto a un grande uomo, stando un passo indietro». La frase ha suscitato numerose reazioni sui social, portando il conduttore a scusarsi dicendo che quel "passo indietro" si riferiva alla scelta di Francesca di stare fuori dai riflettori che inevitabilmente sono puntati su un campione come Valentino.[69]
Ha suscitato molte polemiche la partecipazione del rapper romano Junior Cally, in quanto alcuni testi di sue precedenti canzoni conterrebbero riferimenti al sessismo e al femminicidio.[70] Nonostante il cantautore si sia scusato pubblicamente sui suoi canali social, da più parti è stata chiesta l'esclusione del cantante dalla gara, anche con una petizione online che ha raccolto oltre 20 mila firme;[71] dal comitato Cisl donne del Friuli Venezia Giulia è partita una mobilitazione per boicottare il Festival con l'hashtag #iononguardosanremo; nessun provvedimento è stato preso sulla questione.
Bugo e Morgan sono stati squalificati durante la quarta serata per diverse violazioni del regolamento; tra quelle più evidenti vi è la modifica del testo dell'inedito "Sincero" da parte di Morgan, che lo ha trasformato in un'invettiva contro Bugo, reo a suo dire di aver contribuito la sera precedente al pessimo piazzamento (24° e ultimo posto sia nella classifica della serata che in quella generale) cantando dei pezzi del brano "Canzone d'amore" di Sergio Endrigo che sarebbero invece spettati a Morgan: il testo originale dell'inedito recitava: "Le buone intenzioni, l’educazione, la tua foto profilo, buongiorno e buonasera, e la gratitudine, le circostanze, bevi se vuoi ma fallo responsabilmente, rimetti in ordine tutte le cose, lavati i denti e non provare invidia. Non lamentarti che c’è sempre peggio, ricorda che devi fare benzina. Ma sono solo io […]. Il testo modificato da Morgan diceva: "Le brutte intenzioni, la maleducazione, la tua brutta figura di ieri sera, la tua ingratitudine, la tua arroganza, fai ciò che vuoi mettendo i piedi in testa", "certo il disordine è una forma d'arte", "ma tu sai solo coltivare invidia", "ringrazia il cielo se sei su questo palco, rispetta chi ti ci ha portato dentro e questo sono io" (riferendosi al fatto che secondo lui Bugo ha potuto partecipare al Festival solo grazie alla popolarità del membro dei Bluvertigo). Bugo, una volta sentito tali parole, ha preso dei fogli dallo spartito di Morgan e ha abbandonato il palco (altra grave violazione del regolamento). È la prima volta nella storia del Festival che un concorrente viene squalificato a gara in corso
"""
.data(using: .utf8)!
        
        do {
            try mqtt.connect(username: "admin", password: "Accenture.123!").wait()
            
            let topic1 = "test/topic1"
            let topic2 = "test/topic2"
            try mqtt.subscribe(to: [topic1 : .atLeastOnce, topic2 : .atLeastOnce]).wait()
            
            sleep(70)
//            let message1 = MQTTPubMsg(topic: topic1, payload: "Hello world!".data(using: .utf8)!, retain: false, QoS: .atLeastOnce)
//            try mqtt.publish(message: message1).wait()
//
//            sleep(3)
//            print(bigMessage.count)
//            let message2 = MQTTPubMsg(topic: topic2, payload: bigMessage, retain: false, QoS: .atLeastOnce)
//            try mqtt.publish(message: message2).wait()
            
            sleep(30)
            try mqtt.unsubscribe(from: [topic1, topic2]).wait()
            try mqtt.disconnect().wait()
        } catch {
            XCTFail("\(error)")
        }
        
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
