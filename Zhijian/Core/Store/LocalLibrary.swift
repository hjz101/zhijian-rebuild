// LocalLibrary.swift — 本地书内容仓库 + 离线示例书（Lead 维护）
import Foundation
import Combine

struct LocalChapterRecord: Codable, Hashable {
    var index: Int
    var title: String
    var text: String
}

struct LocalBookRecord: Codable, Hashable {
    var bookId: String
    var chapters: [LocalChapterRecord]
}

@MainActor
final class LocalLibrary: ObservableObject {
    static let shared = LocalLibrary()
    @Published private(set) var books: [String: LocalBookRecord] = [:]
    private let file = "local_library.json"

    private init() {
        books = AppData.load([String: LocalBookRecord].self, file) ?? [:]
    }

    func record(for bookId: String) -> LocalBookRecord? { books[bookId] }

    func save(_ record: LocalBookRecord) {
        books[record.bookId] = record
        AppData.save(books, file)
    }

    /// 离线示例书：不依赖网络，用于验证分页/TTS/备份
    func seedDemoBookIfNeeded(into store: BookStore) {
        let demoId = "demo-local-001"
        if books[demoId] == nil {
            let chapters = DemoText.chapters.enumerated().map { i, c in
                LocalChapterRecord(index: i, title: c.title, text: c.text)
            }
            save(LocalBookRecord(bookId: demoId, chapters: chapters))
        }
        guard let record = books[demoId], !store.books.contains(where: { $0.id == demoId }) else { return }
        var book = Book.local(title: "山居书简", author: "指尖示例", fileName: "山居书简.txt")
        book.id = demoId
        book.totalChapters = record.chapters.count
        book.lastChapter = record.chapters.last?.title
        store.add(book)
    }
}

enum DemoText {
    struct C { let title: String; let text: String }

    static let chapters: [C] = [
        C(title: "第一章 入山", text: """
        清晨的雾还没有散，山道两旁的松针上挂着水珠。我背着一只旧布包，沿着石阶往上走，脚下的青苔被露水打湿，稍不留神就会滑一下。

        朋友说，山顶有一间废弃的书屋，屋主人多年前下山去了，留下满屋的书和一张写着“随意取阅”的木牌。我起初不信，直到在半山腰看见那块被雨洗得发白的路标，上面用墨写着“书庐”两个字。

        走到第三道弯的时候，雾忽然薄了。远处的山脊像一条伏着的兽，天光从它背上慢慢爬过来。我停下来喘气，听见不知名的鸟在林子深处叫，一声长，两声短，像是在给谁报信。

        石阶尽头是一道矮墙，墙头长着蕨。推门进去，院子里有一棵老桂树，树下摆着两条长凳。屋檐下挂着风铃，风一过，声音很轻，像有人翻了一页纸。

        书屋的门没有锁，只虚掩着。我推门，闻见旧纸和木头的气味。那一刻我忽然明白，朋友没有骗我。
        """),
        C(title: "第二章 书庐", text: """
        屋里比外面暗。靠墙是一排顶到房梁的书架，书脊的颜色深浅不一，有些已经褪成灰白。窗下有一张长桌，桌上摊着一本翻开的书，旁边压着一块溪石，石头上有一圈浅浅的水痕。

        我走到桌前，看见那本书停在某一页，页边用铅笔写着几个小字：“此处宜慢读。”字迹很淡，像是写的人怕惊动了什么。

        书架上的书没有分类，也不按年代。游记挨着诗集，农书旁边放着一本讲星象的旧册子。我抽出最薄的一本，封面已经磨掉了一半，只剩下“山中来信”四个字。

        第一页写着：“若你读到这行字，说明山上的雾刚好散了。请坐，不必急着走。”

        我笑了一下，把布包放在脚边，真的坐了下来。窗外的光落在桌面上，慢慢移动，像一只不着急的钟。
        """),
        C(title: "第三章 来信", text: """
        那本《山中来信》其实是一位老人写给自己的信。他每年入山一次，住上十天，把这一年里想不明白的事写在信里，再放回书架。他说，等明年再来读，许多事就已经不必明白了。

        有一封信写得很短：“今日雨后，见蜗牛上墙，行甚缓，然终至檐下。人亦如是。”

        另一封长一些，讲他年轻时在城里做编辑，日夜看稿，眼睛坏了，心也坏了。后来他辞了工作，搬到山里，起初睡不着，听见风声就以为有人在敲门。再后来，他学会在风里睡觉。

        我读到这里，抬头看了一眼门。门关着，风从门缝里进来，吹动桌上的书页。那一刻我并不觉得害怕，反而觉得这间屋子有人气，像主人只是出门打水，很快就会回来。
        """),
        C(title: "第四章 夜谈", text: """
        天快黑的时候，山下上来一个背竹篓的人。他看见我，愣了一下，随后笑了：“今年来得早。”

        我说我不是约好的人。他摆摆手，说约不约都一样，山不认人，只认脚步。他叫阿禾，是山下村子的护林员，隔三差五上来给书屋添灯油、晒书。

        我们坐在桂树下吃他带上来的饭团。他问我读到了哪一封，我说蜗牛那封。他点点头，说那是老人最后一年写的，写完没多久就下山了，再没回来。

        “他把书留在这儿，是给后来的人读的。”阿禾说，“书这种东西，放在箱子里是死物，有人翻，才活。”

        夜里我睡在书屋的偏房。窗纸透进月光，风铃偶尔响一声。我很久没有睡得这样沉。
        """),
        C(title: "第五章 下山", text: """
        第二天早上，雾又起来了。我帮阿禾把院子里的书搬到廊下晒，一本一本摊开，书页在风里轻轻掀动，像一群白色的鸟。

        临走前，我在桌上的留言簿里写了一行字：“昨夜风大，书页自翻至第三十七页，似是主人回来过。”

        阿禾看了，笑说：“他要是看见，会高兴的。”

        下山的路上，我走得很慢。来时的石阶还在，青苔更绿了一些。走到半山腰，我回头看了一眼，书庐已经隐在雾里，只剩屋檐一角，像一页没有读完的书。

        我知道我还会再来。不是为了读完那些书，而是为了在某个起雾的清晨，再听见风铃响一声。
        """),
        C(title: "第六章 附录：山居书目", text: """
        书庐存书目录（残卷，据阿禾口述整理）：

        一、游记类：《西南行记》《山中十日》《渡口手札》《北岭风土记》。

        二、诗文集：《松间集》《晚渡诗稿》《山中来信》《灯下草》。

        三、农桑与草木：《山田岁时记》《草木同名考》《菌谱》《溪鱼图说》。

        四、杂类：《星象旧闻》《纸墨考》《风铃样式录》《蜗牛观察笔记》。

        注：目录不全，且多本已残。屋主留言：“书不必全，读到一句受用的，便不算白来。”

        又注：若有来者续写，请用铅笔，勿用墨。铅笔可以擦去，墨不能。
        """)
    ]
}
