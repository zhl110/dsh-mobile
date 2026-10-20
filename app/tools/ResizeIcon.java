import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;

/**
 * 把一张方图切成 mipmap 五档图标。只需要 JDK，不引第三方库。
 * 用法：java ResizeIcon.java <src.png> <res目录>
 */
public class ResizeIcon {
    static final String[][] DENSITY = {
            {"mdpi", "48"}, {"hdpi", "72"}, {"xhdpi", "96"}, {"xxhdpi", "144"}, {"xxxhdpi", "192"}
    };

    public static void main(String[] a) throws Exception {
        if (a.length < 2) {
            System.err.println("usage: src.png resDir");
            System.exit(2);
        }
        BufferedImage src = ImageIO.read(new File(a[0]));
        for (String[] d : DENSITY) {
            int px = Integer.parseInt(d[1]);
            BufferedImage out = new BufferedImage(px, px, BufferedImage.TYPE_INT_ARGB);
            Graphics2D g = out.createGraphics();
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(src, 0, 0, px, px, null);
            g.dispose();
            File dir = new File(a[1] + "/mipmap-" + d[0]);
            dir.mkdirs();
            File f = new File(dir, "ic_launcher.png");
            ImageIO.write(out, "png", f);
            System.out.println("mipmap-" + d[0] + "/ic_launcher.png " + px + "px " + f.length() + " B");
        }
    }
}
