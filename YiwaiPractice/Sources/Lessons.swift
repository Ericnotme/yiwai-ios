import Foundation

struct Position: Codable, Identifiable {
    let id: String
    let label: String
    let fen: String
    let move: String
    let notation: String
    let line: [String]
    let isMate: Bool
    let explanation: String
    let cues: [String]
    let changed: [String]
}
struct Lesson: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let principle: String
    let positions: [Position]
    static let all: [Lesson] = [
        Lesson(id:"escape", title:"留意王的出口", subtitle:"一格之差，将军还是将死？", principle:"检查所有应将：移王、吃掉将军子、挡将。没有任何合法应将，才是将死。", positions:[
            Position(id:"escape-a",label:"起始题",fen:"6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1",move:"e1e8",notation:"Re8",line:["e1e8"],isMate:true,explanation:"车到 e8，控制整条第八横线。f7、g7、h7 又被黑方自己的兵占住。黑王不能移动，黑方也不能吃车或挡将，因此是将死。",cues:["先想一想：车到 e8 后，黑王能去哪儿？","Re8#：黑王被将军，合法应将为 0。"],changed:[]),
            Position(id:"escape-b",label:"换一个条件",fen:"6k1/5pp1/7p/8/8/8/8/4R1K1 w - - 0 1",move:"e1e8",notation:"Re8",line:["e1e8","g8h7"],isMate:false,explanation:"只把 h7 的黑兵移到 h6。Re8+ 仍将军，但 h7 现在空了，黑王可以 Kh7 逃走。原来的将死结论不再成立。",cues:["与起始题相比，h7 的黑兵到了 h6。","Re8+：黑王有一个合法应将 Kh7。","Kh7：黑王已经离开车的攻击线。"],changed:["h7","h6"]),
            Position(id:"escape-c",label:"再试一个新局面",fen:"6k1/5p1p/6p1/p7/8/3R4/8/1K6 w - - 0 1",move:"d3d8",notation:"Rd8",line:["d3d8","g8g7"],isMate:false,explanation:"这次打开的是 g7。Rd8+ 后黑王可以 Kg7。要记住的是检查逃生格，而不是记住 h7 这个名字。",cues:["车换到 d3，先独立检查黑王周围。","Rd8+：g7 是合法逃生格。","Kg7：王安全，第一步没有将死。"],changed:["g7","g6"])
        ]),
        Lesson(id:"protection",title:"谁在保护将军子",subtitle:"后走到王面前，也可能被吃。",principle:"将军子的保护必须真实存在。王不能走到被攻击的格子，也不能吃有保护的后。",positions:[
            Position(id:"protection-a",label:"起始题",fen:"7k/8/8/5K2/8/8/6Q1/8 w - - 0 1",move:"g2g7",notation:"Qg7",line:["g2g7","h8g7"],isMate:false,explanation:"白王在 f5，保护不到 g7。Qg7+ 后，黑王可以 Kxg7 吃掉没有保护的后。将军不是将死。",cues:["白王在 f5，能保护 g7 吗？","Qg7+：黑王可以吃掉将军的后。","Kxg7：后被吃掉，将军解除。"],changed:[]),
            Position(id:"protection-b",label:"换一个条件",fen:"7k/8/5K2/8/8/8/6Q1/8 w - - 0 1",move:"g2g7",notation:"Qg7",line:["g2g7"],isMate:true,explanation:"白王移到 f6，正好保护 g7。黑王不能 Kxg7，g8、h7 也受白后控制。没有合法应将，所以 Qg7# 是将死。",cues:["白王只从 f5 移到了 f6。","Qg7#：白王保护后，黑王没有合法应将。"],changed:["f5","f6"]),
            Position(id:"protection-c",label:"再试一个新局面",fen:"k7/1p6/7p/8/4B3/8/1Q6/6K1 w - - 0 1",move:"b2b7",notation:"Qxb7",line:["b2b7"],isMate:true,explanation:"Qxb7# 成立。保护后的换成了 e4 的象，经 d5、c6 保护 b7。黑王不能吃后，a7、b8 也被后控制。",cues:["留意 e4 的象与 b7 的关系。","Qxb7#：象保护后，所有逃生格被封住。"],changed:["e4","b7"])
        ]),
        Lesson(id:"relevance",title:"变化真的有关吗",subtitle:"棋盘变了，结论一定会变吗？",principle:"只看变化有没有影响移王、吃子或挡将。远处的棋子也可能是有效防守者。",positions:[
            Position(id:"relevance-a",label:"起始题",fen:"7k/p7/5K2/8/8/8/6Q1/8 w - - 0 1",move:"g2g7",notation:"Qg7",line:["g2g7"],isMate:true,explanation:"白王 f6 保护 g7 的后。黑王没有逃生格，a7 的黑兵也不能吃后或挡将，所以 Qg7# 是将死。",cues:["远处 a7 有一枚黑兵。","Qg7#：黑兵不能解除这次将军。"],changed:[]),
            Position(id:"relevance-b",label:"换一个条件",fen:"7k/8/p4K2/8/8/8/6Q1/8 w - - 0 1",move:"g2g7",notation:"Qg7",line:["g2g7"],isMate:true,explanation:"黑兵从 a7 到 a6，并没有改变后受到的保护，也没有增加合法应将。两局都是 Qg7#。看见变化，不代表结论必须相反。",cues:["黑兵从 a7 移到了 a6。","Qg7#：这次变化与能否应将无关。"],changed:["a7","a6"]),
            Position(id:"relevance-c",label:"再试一个新局面",fen:"7k/r7/5K2/8/8/8/6Q1/8 w - - 0 1",move:"g2g7",notation:"Qg7",line:["g2g7","a7g7"],isMate:false,explanation:"这次 a7 是黑车。Qg7+ 后它可以 Rxg7 吃掉将军的后。即使白王能再吃回车，第一步也没有将死。",cues:["a7 换成了黑车，检查它能做什么。","Qg7+：黑车有合法应将 Rxg7。","Rxg7：将军子被吃，黑王解围。"],changed:["a7"])
        ])
    ]
}
