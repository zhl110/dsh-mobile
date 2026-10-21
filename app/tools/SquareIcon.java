import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;
import java.util.ArrayDeque;

/**
 * 把"分享导出"那种带白角的圆角方图，补成满幅方图（给 Android 启动器自己套形状用）。
 *
 * 为什么要它（2026-10-21）：他放进 app/icon 的三张候选里，两张四角是纯白 255,255,255 —— 那是
 * 导出 App 的圆角底板，不是图标内容。直接把这种图当启动器图标，桌面上会露出四个白角
 * （现在这一版 icon-src.png 也有同样的毛病，四角 251,252,252）。
 *
 * 算法分三步，关键是每一处都**只认连通到图像边界的那一块**：
 *   1) 从四条边向内洪泛"亮"像素（亮度 >= 170）⇒ 圆角外的白底板；
 *   2) 把底板往里再扩 3 个像素（把那圈抗锯齿灰边一起算进来，不然补完会留一道浅灰的圈）；
 *   3) 从紧挨着它的**深色**像素（亮度 < 100）出发，一圈圈把底色推过去。
 * 鲸鱼的白肚皮、白色描边都被深色围住、不连边界 ⇒ 一根像素都不会被碰。
 * 前两版都栽在"来源不够严"：第一版没有任何亮度下限，补出来四角是 237,240,247 的浅灰；
 * 第二版下限写成 150，补出来还是 124–146 的灰 —— 因为抗锯齿那圈正好落在这个区间。
 *
 * 用法：java SquareIcon.java <in.png> <out.png> [输出边长]
 */
public class SquareIcon {
    static final int LIGHT = 170;   // 亮度 >= 170 视为"亮"（底板候选）
    static final int DARK  = 100;   // 亮度 < 100 才允许当"填充色来源"（这是实测调的：150 太松）
    static final int GROW  = 3;     // 底板往里扩几圈，吃掉抗锯齿灰边

    public static void main(String[] a) throws Exception {
        if (a.length < 2) {
            System.err.println("usage: java SquareIcon.java <in.png> <out.png> [size]");
            System.exit(2);
        }
        BufferedImage src = ImageIO.read(new File(a[0]));
        if (src == null) { System.err.println("读不了：" + a[0]); System.exit(1); }
        int w = src.getWidth(), h = src.getHeight();
        int[] px = src.getRGB(0, 0, w, h, null, 0, w);
        System.out.println("输入 " + a[0] + " " + w + "x" + h);

        boolean[] fill = new boolean[w * h];
        ArrayDeque<Integer> q = new ArrayDeque<>();
        for (int x = 0; x < w; x++) { seed(px, fill, q, x, 0, w); seed(px, fill, q, x, h - 1, w); }
        for (int y = 0; y < h; y++) { seed(px, fill, q, 0, y, w); seed(px, fill, q, w - 1, y, w); }
        int flooded = 0;
        while (!q.isEmpty()) {
            int i = q.poll(); flooded++;
            int x = i % w, y = i / w;
            if (x > 0) seed(px, fill, q, x - 1, y, w);
            if (x < w - 1) seed(px, fill, q, x + 1, y, w);
            if (y > 0) seed(px, fill, q, x, y - 1, w);
            if (y < h - 1) seed(px, fill, q, x, y + 1, w);
        }

        // 第 2 步：把底板往里扩 GROW 圈（不看颜色，直接把挨着的像素算进来 —— 抗锯齿那圈灰边就在这儿）
        int eaten = 0;
        for (int k = 0; k < GROW; k++) {
            java.util.ArrayList<Integer> add = new java.util.ArrayList<>();
            for (int i = 0; i < w * h; i++) {
                if (fill[i]) continue;
                int x = i % w, y = i / w;
                if ((x > 0 && fill[i - 1]) || (x < w - 1 && fill[i + 1]) ||
                    (y > 0 && fill[i - w]) || (y < h - 1 && fill[i + w])) add.add(i);
            }
            for (int i : add) { fill[i] = true; eaten++; }
            if (add.isEmpty()) break;
        }
        System.out.println("底板像素：" + flooded + "，往里扩 " + GROW + " 圈又吃进：" + eaten + "（合计占 " +
                String.format("%.2f", (flooded + eaten) * 100.0 / (w * h)) + "%）");

        // 第 3 步：从挨着底板的暗像素出发，把颜色推进去
        boolean[] done = new boolean[w * h];
        ArrayDeque<Integer> fq = new ArrayDeque<>();
        for (int i = 0; i < w * h; i++) {
            if (fill[i] || done[i] || lum(px[i]) >= DARK) continue;   // 来源必须是暗像素
            int x = i % w, y = i / w;
            if ((x > 0 && fill[i - 1]) || (x < w - 1 && fill[i + 1]) ||
                (y > 0 && fill[i - w]) || (y < h - 1 && fill[i + w])) {
                done[i] = true; fq.add(i);
            }
        }
        while (!fq.isEmpty()) {
            int i = fq.poll();
            int x = i % w, y = i / w;
            int[] nb = { x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1 };
            for (int j : nb) {
                if (j < 0 || done[j] || !fill[j]) continue;
                px[j] = px[i];
                done[j] = true;
                fq.add(j);
            }
        }
        int left = 0;
        for (int i = 0; i < w * h; i++) if (fill[i] && !done[i]) left++;
        System.out.println("补完还剩没填到的底板像素：" + left + "（应为 0）");

        BufferedImage out = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        out.setRGB(0, 0, w, h, px, 0, w);
        if (a.length >= 3) {
            int px2 = Integer.parseInt(a[2]);
            BufferedImage scaled = new BufferedImage(px2, px2, BufferedImage.TYPE_INT_RGB);
            Graphics2D g = scaled.createGraphics();
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(out, 0, 0, px2, px2, null);
            g.dispose();
            out = scaled;
        }
        ImageIO.write(out, "png", new File(a[1]));
        System.out.println("写出 " + a[1] + " " + out.getWidth() + "x" + out.getHeight() +
                " " + new File(a[1]).length() + " B");
        for (int[] p : new int[][]{{2, 2}, {out.getWidth() - 3, 2}, {2, out.getHeight() - 3},
                {out.getWidth() - 3, out.getHeight() - 3}}) {
            int c = out.getRGB(p[0], p[1]);
            System.out.println("  角(" + p[0] + "," + p[1] + ")=" +
                    ((c >> 16) & 255) + "," + ((c >> 8) & 255) + "," + (c & 255));
        }
    }

    static int lum(int c) {
        return (((c >> 16) & 255) * 299 + ((c >> 8) & 255) * 587 + (c & 255) * 114) / 1000;
    }

    static void seed(int[] px, boolean[] fill, ArrayDeque<Integer> q, int x, int y, int w) {
        int i = y * w + x;
        if (fill[i] || lum(px[i]) < LIGHT) return;
        fill[i] = true; q.add(i);
    }
}
