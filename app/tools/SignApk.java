import com.android.apksig.ApkSigner;

import java.io.FileInputStream;
import java.io.File;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.List;

/**
 * 最小 APK 签名器：apksig 库没有 main，这里给一个。
 * 用法：java -cp apksig.jar SignApk.java <in.apk> <out.apk> <keystore> <alias> <password>
 * v1 关掉（minSdk 26，v2/v3 足够），v3 用来带上 rot 轮换信息。
 */
public class SignApk {
    public static void main(String[] a) throws Exception {
        if (a.length < 5) {
            System.err.println("usage: in.apk out.apk keystore alias password");
            System.exit(2);
        }
        char[] pw = a[4].toCharArray();
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (FileInputStream in = new FileInputStream(a[2])) {
            ks.load(in, pw);
        }
        PrivateKey key = (PrivateKey) ks.getKey(a[3], pw);
        List<X509Certificate> chain = new ArrayList<X509Certificate>();
        for (Certificate c : ks.getCertificateChain(a[3])) {
            chain.add((X509Certificate) c);
        }
        ApkSigner.SignerConfig cfg = new ApkSigner.SignerConfig.Builder(
                a[3], key, chain).build();
        new ApkSigner.Builder(java.util.Collections.singletonList(cfg))
                .setMinSdkVersion(26)
                .setV1SigningEnabled(false)
                .setV2SigningEnabled(true)
                .setV3SigningEnabled(true)
                .setV4SigningEnabled(false)
                .setInputApk(new File(a[0]))
                .setOutputApk(new File(a[1]))
                .build()
                .sign();
        System.out.println("signed: " + a[1] + "  (v2+v3, cert " + chain.get(0).getType() + ")");
    }
}
