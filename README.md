# GrowthForecast/RRDtool チューニング秘伝の書

First Edition: 2014/01. Last Modified: 2014/06/10. Author: [@sonots](https://twitter.com/sonots)

* [はじめに](#%E3%81%AF%E3%81%98%E3%82%81%E3%81%AB)
* [GrowthForecast のチューニング](#growthforecast-%E3%81%AE%E3%83%81%E3%83%A5%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0)
  * [事前知識 - GrowthForecast がどのように動いているか](#%E4%BA%8B%E5%89%8D%E7%9F%A5%E8%AD%98---growthforecast-%E3%81%8C%E3%81%A9%E3%81%AE%E3%82%88%E3%81%86%E3%81%AB%E5%8B%95%E3%81%84%E3%81%A6%E3%81%84%E3%82%8B%E3%81%8B)
  * [マシンスペック](#%E3%83%9E%E3%82%B7%E3%83%B3%E3%82%B9%E3%83%9A%E3%83%83%E3%82%AF)
  * [ベンチマークツール - growthforecast-client bench](#%E3%83%99%E3%83%B3%E3%83%81%E3%83%9E%E3%83%BC%E3%82%AF%E3%83%84%E3%83%BC%E3%83%AB---growthforecast-client-bench)
  * [MySQL のチューニング](#mysql-%E3%81%AE%E3%83%81%E3%83%A5%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0)
  * [web-max-workers の数を増やす](#web-max-workers-%E3%81%AE%E6%95%B0%E3%82%92%E5%A2%97%E3%82%84%E3%81%99)
  * [RRAの数を減らす](#rra%E3%81%AE%E6%95%B0%E3%82%92%E6%B8%9B%E3%82%89%E3%81%99)
  * [short worker の停止](#short-worker-%E3%81%AE%E5%81%9C%E6%AD%A2)
  * [disable subtract](#disable-subtract)
  * [まとめ](#%E3%81%BE%E3%81%A8%E3%82%81)
* [RRDtool のチューニング](#rrdtool-%E3%81%AE%E3%83%81%E3%83%A5%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0)
  * [事前知識 - RRDファイルの構造](#%E4%BA%8B%E5%89%8D%E7%9F%A5%E8%AD%98---rrd%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%81%AE%E6%A7%8B%E9%80%A0)
  * [マシンスペック](#%E3%83%9E%E3%82%B7%E3%83%B3%E3%82%B9%E3%83%9A%E3%83%83%E3%82%AF)
  * [ベンチマークツール - benchmark_rrd.pl](#%E3%83%99%E3%83%B3%E3%83%81%E3%83%9E%E3%83%BC%E3%82%AF%E3%83%84%E3%83%BC%E3%83%AB---benchmark_rrdpl)
  * [fadvise を使う](#fadvise-%E3%82%92%E4%BD%BF%E3%81%86)
  * [rrdcached を使う](#rrdcached-%E3%82%92%E4%BD%BF%E3%81%86)
  * [SSD を使う](#ssd-%E3%82%92%E4%BD%BF%E3%81%86)
  * [tmpfs を使う](#tmpfs-%E3%82%92%E4%BD%BF%E3%81%86)
  * [まとめ](#%E3%81%BE%E3%81%A8%E3%82%81)
* [総論](#%E7%B7%8F%E8%AB%96)

# はじめに

GrowthForecast/RRDtool チューニングのために実施したパフォーマンス測定、およびその結果を記す。

# GrowthForecast のチューニング

## 事前知識 - GrowthForecast がどのように動いているか

cf. [http://kazeburo.github.io/GrowthForecast/index.ja.html#gf_internal](http://kazeburo.github.io/GrowthForecast/index.ja.html#gf_internal)

> GrowthForecastはRound Robbin Databaseおよびグラフ描画のツールとしてRRDtoolを利用しています。

> APIのエンドポイントに送信されたデータはRDMBSに一旦保存されます。Workerが定期的に動作し、RDBMSからデータを読み出し、RRDファイルを更新しています。その際、GrowthForecastのworkerは、現在の値に加えて、一つ前との差分をsubtractデータとして格納しています。

> subtractデータをグラフのソースとして利用することで、データの変化量を可視化することができます

![GF Internal](http://kazeburo.github.io/GrowthForecast/img/gf_internal.png)

ポイント

1. GFにデータをPOSTすると、DBにUPDATE文が走る
2. 定期的(normal 5分とshort 1分)に動作する Worker が DB から値を読み込んで rrdupdate をかける。
3. グラフ参照時に rrdgraph が実行され、画像が生成される。

## マシンスペック

検証に利用したマシンのスペックは以下の通りである。クライアントサイド(benchスクリプトを実行)、サーバサイド(GrowthForecastを実行)の２台用意。

HDD Server

|CPU | Xeon X5650 2.66GHz x 2 (24コア)|
|----|--------------------------------|
|メモリ  | 60G|
|ディスク | 146G(15000rpm) x 8  [SAS-HDD]  (RAID1+0)|

## ベンチマークツール - growthforecast-client bench

GrowthForecast の HTTP API のベンチマークには、Ruby クライアントである
https://github.com/sonots/growthforecast-client に bench コマンドを追加してあるのでそれを使える。
当然 GrowthForecast が動いているホストとは別のホストから叩くべきである。

```bash
$ gem install growthforecast-client
$ growthforecast-client bench http://fqdn.to.growthforecast:5125 -n 1000 -c 10
```

本気でぶん回すと TIME_WAIT なソケットが増えてローカルポートを食いつぶすので、カーネルパラメータをいじっておく

```bash
$ sudo sysctl -w net.ipv4.ip_local_port_range="10000 64000"
$ sudo sysctl -w net.ipv4.tcp_tw_reuse=1
```

limits も引きあげておく。ログインしなおして ulimit -n で確認

```bash
$ sudo vi /etc/security/limits.conf  
* soft nofile 65536
* hard nofile 65536
```

注釈：これはベンチマークツールのチューニングであり、GrowthForecast のチューニングではない。

## MySQL のチューニング

GrowthForecast は sqlite (デフォルト) と MySQL に対応している。
速度が必要な場合は、MySQL に切り替え、MySQL のチューニングをすべし！

少なからず innodb_buffer_pool_size と innodb_log_file_size ぐらいは大きくしておくべし!

```
[mysqld]
# innodb plugin for mysql >= 5.1.38, comment out for mysql >= 5.5 because it is default.
ignore-builtin-innodb
plugin-load=innodb=ha_innodb_plugin.so;innodb_trx=ha_innodb_plugin.so;innodb_locks=ha_innodb_plugin.so;innodb_lock_waits=ha_innodb_plugin.so;innodb_cmp=ha_innodb_plugin.so;innodb_cmp_reset=ha_innodb_plugin.so;innodb_cmpmem=ha_innodb_plugin.so;innodb_cmpmem_reset=ha_innodb_plugin.so

datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
user=mysql
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0

slow_query_log      = 1
slow_query_log_file = /var/lib/mysql/slow.log
long_query_time     = 0.1

max_connections=1024
thread_cache       = 600
thread_concurrency = 8
table_cache        = 8192
back_log           = 10240

query_cache_size    =    0
query_cache_type    =    0

# global buffer
key_buffer_size                 = 32M
innodb_buffer_pool_size         = 4G # assign 80% of system memory!
innodb_log_buffer_size          = 8M
innodb_additional_mem_pool_size = 10M

# thread buffer
sort_buffer_size        = 1M
myisam_sort_buffer_size = 64K
read_buffer_size        = 1M

# innodb
innodb_flush_log_at_trx_commit  = 0
innodb_lock_wait_timeout        = 5
innodb_flush_method             = O_DIRECT
innodb_adaptive_hash_index      = 0
innodb_thread_concurrency       = 30
innodb_read_io_threads          = 16
innodb_write_io_threads         = 16
innodb_io_capacity              = 200
innodb_stats_on_metadata        = Off
# Set the log file size to about 25% of the buffer pool size
# => Well, seems i don't need such much cf. http://nippondanji.blogspot.jp/2009/01/innodb.html
innodb_log_file_size            = 128M
innodb_log_files_in_group       = 2

[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
```

再起動

```bash
$ sudo rm /var/lib/mysql/ib_logfile*
sudo service mysql restart
```

性能評価結果

| Storage             | # of web-max-workers | # of client concurrency | Result: Requests per second [#/sec] | Result: Time per request [ms] |
|---------------------|----------------------|-------------------------|-------------------------------------|-------------------------------|
| sqlite              | 4                    | 4                       | 898.399                             | 1.113                         |
|                     |                      | 24                      | 1197.764                            | 0.834                         |
|                     | 24                   | 24                      | 1236.457                            | 0.808                         |
|                     |                      | 128                     | 1343.334                            | 0.744                         |
|                     | 128                  | 128                     | 1164.968                            | 0.858                         |
|                     | 256                  | 256                     | 1078.667                            | 0.927                         |
| MySQL 5.1 (Default) | 4                    | 4                       | 87.194                              | 11.468                        |
|                     |                      | 24                      | 108.919                             | 9.181                         |
|                     | 24                   | 24                      | 725.795                             | 1.377                         |
|                     |                      | 128                     | 706.437                             | 1.415                         |
|                     | 128                  | 128                     | 3072.649                            | 0.325                         |
|                     | 256                  | 256                     | error                               | error                         |
| MySQL 5.1 (Tuned)   | 4                    | 4                       | 898.901                             | 1.112                         |
|                     |                      | 24                      | 1159.160                            | 0.862                         |
|                     | 24                   | 24                      | 3827.799                            | 0.261                         |
|                     |                      | 128                     | **3922.552**                        | 0.254                         |
|                     | 128                  | 128                     | 3533.777                            | 0.282                         |
|                     | 256                  | 256                     | 3294.454                            | 0.3035                        |

結論

* MySQL をチューニングして使おう(チューニングしないと sqlite よりも遅い)

## web-max-workers の数を増やす

v0.62 から --web-max-workers オプションが使える。=> [pull/27](https://github.com/kazeburo/GrowthForecast/pull/27)

結果

1) --web-max-workers 4 (デフォルト)

```
Requests per second: 1219.3904675353494 [#/sec] (mean)
Time per request:    0.8200818578 [ms] (mean)
```

2) --web-max-workers 24

```
Requests per second: 4058.445933130032 [#/sec] (mean)
Time per request:    0.24639973440000001 [ms] (mean)
```

結論

* --web-max-workers [CPUコア数] 程度にすると良い。
* それ以上にしてもあまり効果なし。
* StarletをMonocerosに変えてもあまり効果なし。
* デフォルトの4に比べて3.3倍の高速化という結果。
* これで 4000 requests / sec (＝ 240,000 requests / min) ぐらい捌けた。
* 0.5 msec or die

この時点でボトルネックは GF worker になる(なった)。

## RRAの数を減らす

[lib/GrowthForecast/RRD.pm#L27-L39](https://github.com/kazeburo/GrowthForecast/blob/d3fb8e8946100b8b001856deedb804a000894d2b/lib/GrowthForecast/RRD.pm#L27-L39)

```perl
    my @param = (
        '--start', $timestamp - 10, # -10 as rrdcreate's default does (now - 10s)
        '--step', '300',
        "DS:num:${dst}:600:U:U",
        'RRA:AVERAGE:0.5:1:1440',  #5分, 5日
        'RRA:AVERAGE:0.5:6:1008', #30分, 21日
        'RRA:AVERAGE:0.5:24:1344', #2時間, 112日
        'RRA:AVERAGE:0.5:288:2500', #24時間, 500日
        'RRA:MAX:0.5:1:1440',  #5分, 5日
        'RRA:MAX:0.5:6:1008', #30分, 21日
        'RRA:MAX:0.5:24:1344', #2時間, 112日
        'RRA:MAX:0.5:288:2500', #24時間, 500日
    );
```

RRAの数を減らせば rrdupdate を高速化できる。たとえば AVERAGE なんていらねーぜ、という人は AVERAGE 分を削ればおそらく２倍ほど早くなる。おそらくこんかんじになる => https://gist.github.com/sonots/d94aeb75c4021477a523

※ 筆者注：自分はやってません。

## short worker の停止

GrowthForecast は normal worker (5分おき)と short worker (1分おき) の２つを動かしている。
当初は normal worker (5分おき)のみであったが、1分単位の解像度でグラフを見たいという要望があり、short worker (1分おき)が追加されたという経緯があり、下位互換性のために normal worker も残っているという状況。

worker が２つ動作することによって、ディスクアクセスが(５分おきに)２倍になっているため、short worker を止め、normal worker の更新間隔を1分おきにするという手を使うと、２倍の高速化を望める。

次のパッチをあて、normal worker を 60 sec で動かすように変更。RRD ファイルの step も 60 sec に変更。

https://gist.github.com/sonots/b327a785ba6d4af879b8

perl growthforecast.pl --disable-1min-worker として起動し、short worker を無効化。

## disable subtract

GrowthForecast は subtract グラフ(前回 POST した値との差分を値にするグラフ)を作る機能があるが、v0.81 からその機能を無効化する --disable-subtract オプションの機能が入った。

https://github.com/kazeburo/GrowthForecast/pull/50

これにより次のような効果がある。

1. subtract グラフの値を計算するために発行していた N+1 クエリを１クエリに削減することができる。
2. GrowthForecast は１つの rrdfile に２つの DS(num, sub) を作成しているが、sub が不要になり、ディスクサイズおよびディスクアクセスを半分に減らすことができる。

実測として、６万グラフを更新するのに 50 sec かかっていたものを 10 sec に短縮することができた。５倍の高速化。

perl growthforecast.pl --disable-subtract として起動し、subtract 機能を無効化。

## まとめ

1. Webサイドの高速化

    1. MySQLをチューニングしましょう
    2. --web-max-workers を増やすことで3.3倍の高速化

2. Workerサイドの高速化

    1. --disalble-1min-worker により2倍の高速化 (要[パッチ](https://gist.github.com/sonots/b327a785ba6d4af879b8))
    2. --disable-subtract により5倍の高速化

# RRDtool のチューニング

## 事前知識 - RRDファイルの構造

http://oss.oetiker.ch/rrdtool-trac/wiki/TuningRRD の文書をかいつまんで解説する。

RRDtool の高速化をするには、如何にディスクキャッシュ(メモリ)に載せるかがポイントとなる。
この文書はディスクキャッシュに載せるための Tuning 方法のポイントを指南している。

**RRDtool File Format:**

```plain
 +-------------------------------+
  | RRD Header                    |
  |-------------------------------|
  | DS Header (one per DS)        |
  |-------------------------------|
  | RRA Header (one per RRA)      |
  |===============================| < 1 kByte (normally)
  | RRA Data Area (first RRA)     |
  ................................. The bulk of the space
  | RRA Data Area (last RRA)      |
  +-------------------------------+
```

RRDファイルのフォーマットは上図のようになっている。rrdupdate をかけると、ヘッダ読み込み(小さい) -> ヘッダ書き込み(小さい) -> RRAデータの書き込み(大きい)を行う。

※ 筆者注：ヘッダのデータが全てディスクキャッシュに載っているとディスクアクセスが減り速くなる。

**Memory Sizing:**

ヘッダ 4k と RRA のアクティブな最低でも１ブロック 4k、あわせて 8k のディスクキャッシュが RRD ファイルごとに必要となる。
なので例えば 100,000 RRD ファイルならば、

```
   100,000 * 8kByte per RRD ~ 800 MByte Buffer Cache
```

ということで 800Mbyte のディスクキャッシュ領域が必要となる。

※ 筆者注：全 RRD ファイルが載るぐらいのメモリを確保しておくと確実。

**Suppressing Read-Ahead:**

OSの機能により、ディスク読み込み時に何ブロックか先まで読んでしまうが、rrdupdate で必要なのはヘッダ分でしかなく、無駄となる。

そこで、posix_fadvise を使って、OS に random アクセスするよ、と伝えて先読みを止める。

fadvise を利用した tuning についてはあとで触れる。

**Preserving Buffer Cache:**

ディスクキャッシュのサイズを増やせば rrdupdate は効率的になる。
ただし、rrdtool graph で画像を生成するとディスクキャッシュが大量に使用されて、
その間 rrdupdate でディスクキャッシュを有効利用できなくなる.

ここでも、posix_fadvise を使って、RRDヘッダと今アクセスしているデータのみディスクキャッシュを使うよう指定し、
rrdtool graph の結果がディスクキャッシュに載らないようにする。

**VM Optimizations:**

ページキャッシュ周りのカーネルパラメタをいじると良い。

```
$ sudo sysctl -A | grep vm.dirty
vm.dirty_background_ratio = 10
vm.dirty_background_bytes = 0
vm.dirty_ratio = 20
vm.dirty_bytes = 0
vm.dirty_writeback_centisecs = 500
vm.dirty_expire_centisecs = 3000
```

※ 筆者注：が、たいした効果はなかったため、うちではいじっていない。

**その他参考文献:**

* http://2007.jres.org/planning/slides/136.pdf
* https://www.usenix.org/legacy/event/lisa07/tech/full_papers/plonka/plonka.pdf

## マシンスペック

検証に利用したマシンのスペックは以下の通りである。

HDD Server

|CPU | Xeon X5650 2.66GHz x 2 (24コア)|
|----|--------------------------------|
|メモリ  | 60G|
|ディスク | 146G(15000rpm) x 8  [SAS-HDD]  (RAID1+0)|

## ベンチマークツール - benchmark_rrd.pl

rrdupdate のベンチマークには、
[benchmark_rrd.pl](https://github.com/kazeburo/GrowthForecast/blob/master/eg/benchmark_rrd.pl) というものを作って GrowthForecast に突っ込んであるのでそれを使える。

GrowthForecast のメソッド経由で RRDs::create や RRDs::update を呼ぶようにしているが、.so レベルで rrdupdate と共通なのでパフォーマンスに差は出ないはず。
以下のようにして使う。計測の前に drop cache しておくべし。

```bash
$ perl eg/benchmark_rrd.pl -n [RRD数] --create
743.413 sec to create [RRD数] graphs.
$ echo 3 | sudo tee /proc/sys/vm/drop_caches
# Drop disk cache before measurements
$ perl eg/benchmark_rrd.pl -n [RRD数] -r 3 (3回連続実行)
1.901 sec to update [RRD数] graphs.
0.030 sec to update [RRD数] graphs.
0.028 sec to update [RRD数] graphs.
```

ヘルプを貼っておく。

```
NAME
       benchmark_rrd.pl - Benchmark RRD
SYNOPSIS
       $ benchmark_rrd.pl
DESCRIPTION
           Benchmark RRD
OPTIONS
       --data-dir
           A directory where sqlite file is stored. Default: `data`.
       -n --number
           The number of RRD file updated (and created if first time execution). Default: 1.
       -f --from
           The starting number of RRD file creation or updating. Default: 1
       -r --repeat
           The number of repititions. Default: 1
       -p --parallel
           The number of parallel forks. Default: 1 (not implemented yet)
       -c --create
           Benchmark the creation of RRD files. Default: false, which means benchmark the updating (create RRD files unless already exist)
       -s --short
           Benchmark the 1min rrd data. Default: false, which means benchmark the normal rrd
       -m --md5
           Create RRD files of md5ed names as GrowthForecast does. Default: false, which means integer names.
       -h --help
           Display help
       AUTHOR
           Naotoshi Seo <sonots {at} gmail.com>
       LICENSE
           This library is free software; you can redistribute it and/or modify it
           under the same terms as Perl itself.
```

## fadvise を使う

[TuningRRD](http://oss.oetiker.ch/rrdtool-trac/wiki/TuningRRD)のページに載っていたように、
fadvise(2) を使って、readahead を止める、buffer cache をpreserve する、といった施策を試してみる。

fadvise(2) システムコールをファイルに適用するツールとして、http://pages.cs.wisc.edu/~plonka/fadvise/ があるが、
複数オプションを１度に適用することができず辛かったので、それを fork して少しいじったものがこちらにある => https://github.com/sonots/fadvise

次のように利用する。注意： 60,000 rrd ファイルで１時間ぐらいかかる。

```
~/GrowthForecast/data> ls | grep rrd | xargs -n 1 perl ~/fadvise -verbose -random -dontneed
```

**結果**

1) fadvise なし

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
| --------- |:----------------------:|:-------:| -------:|
|1000|1.901|0.030|0.028|
|5000|13.857|0.319|0.146|
|10000|74.367|0.924|0.304|
|20000|101.990|4.249|0.621|
|40000|280.950|57.372|4.628|
|60000|598.367|153.301|96.123|

2) fadvise あり

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
|-------|---------------------------------|-------|------|
|1000|4.295|0.031|0.030|
|5000|25.225|0.375|0.159|
|10000|54.847|1.254|0.329|
|20000|105.071|49.942|0.922|
|40000|238.121|218.047|8.310|
|60000|485.827|373.206|24.343|

**結論**

1. 1.2倍程度の速度向上が見込めた。
2. ただし、6万ファイルに fadvise をあてるのに１時間ほどかかる。新しいグラフができた場合、再度 fadvise をあてる必要があり運用に難あり。

## rrdcached を使う

GrowthForecast v0.70 から --rrdcached オプションが追加されており、
rrdcached を利用することができるようになっている。=> [pull/30](https://github.com/kazeburo/GrowthForecast/pull/30)

rrdcached に送ったデータは、定期的にまとめて更新されるようになっており、うまくハマれば高速化が見込める。

[rrdcached ありなし性能評価結果](https://github.com/kazeburo/GrowthForecast/blob/master/eg/benchmark_rrd.md)

**結論**

1. ディスクキャッシュに載っていない場合、1.5 倍の速度向上が見込めた。
2. ディスクキャッシュに載っている場合、大きな差はでなかった。

## SSD を使う

SSDマシンを用意して比較してみた。

HDD Machine

|CPU | Xeon X5650 2.66GHz x 2 (24コア)|
|----|--------------------------------|
|メモリ  | 60G|
|ディスク | 146G(15000rpm) x 8  [SAS-HDD]  (RAID1+0)|

SSD Machine

|CPU	| Xeon X5650 2.66GHz x 2 (24コア) |
|-----|---------------------------------|
|メモリ	| 60G |
|ディスク | 60G x 8  [SATA-SSD] (RAID1+0) |


**結果**

1) HDD

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
| --------- |:----------------------:|:-------:| -------:|
|1000|1.901|0.030|0.028|
|5000|13.857|0.319|0.146|
|10000|74.367|0.924|0.304|
|20000|101.990|4.249|0.621|
|40000|280.950|57.372|4.628|
|60000|598.367|153.301|96.123|

2) SSD

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
| --------- |:----------------------:|:-------:| -------:|
|1000|4.246|0.033|0.031|
|5000|18.697|0.161|0.156|
|10000|28.612|0.459|0.334|
|20000|56.709|4.472|0.619|
|40000|209.408|3.526|1.627|
|60000|324.832|6.408|1.762|

**結論および考察**

1. ディスクキャッシュに載っていない状態で、1.8倍程度の高速化
2. ディスクキャッシュに載っている状態で、安定した速さ。HDD の場合、パフォーマンスのブレが大きい。ディスクキャッシュに載っているように見えるのだが([Sys-PageCache](http://d.hatena.ne.jp/hirose31/20130913/1379069149)を使って確認)、HDD はなぜか遅くなったりする。

## tmpfs を使う

ディスクキャッシュに載らないなら、tmpfs に入れて全部メモリに載せてしまえばいいじゃない。

**見積もり:**

RRDファイルが全てメモリに載るか見積もるための計算式を記す。

RRDファイルの容量は RRA の定義式および、DSの数から見積もることができる。

```
RRA:CF:xff:steps:rows
```

cf. http://www.itmedia.co.jp/enterprise/articles/0705/30/news022_3.html

![RRA](http://image.itmedia.co.jp/enterprise/articles/0705/30/l_fig07_02.gif)


容量の計算は単純で、rows * 8 bytes となる。例えば、GrowthForecast の場合は、

```bash
    my @param = (
        '--start', $timestamp - 10, # -10 as rrdcreate's default does (now - 10s)
        '--step', '300',
        "DS:num:sub:600:U:U",
        'RRA:AVERAGE:0.5:1:1440',  #5分, 5日
        'RRA:AVERAGE:0.5:6:1008', #30分, 21日
        'RRA:AVERAGE:0.5:24:1344', #2時間, 112日
        'RRA:AVERAGE:0.5:288:2500', #24時間, 500日
        'RRA:MAX:0.5:1:1440',  #5分, 5日
        'RRA:MAX:0.5:6:1008', #30分, 21日
        'RRA:MAX:0.5:24:1344', #2時間, 112日
        'RRA:MAX:0.5:288:2500', #24時間, 500日
    );
```

であるので、

```
(1440 + 1008 + 1344 + 2500 + 1440 + 1008 + 1344 + 2500) * 8 = 100,672 バイト
```

となり、さらに DS が num と sub の２つあるので、その２倍の 201,344 バイト程度となる。
試しにファイルを１つ作ってみて、容量を見れば確実。

```
$ ls -l data/*.rrd | head -1
-rw-rw-r-- 1 seo.naotoshi seo.naotoshi  204104  6月 10 02:15 ffd52f3c7e12435a724a8f30fddadd9c.rrd
```

これがすべて載るだけのメモリを用意できるのであれば、tmpfs に全て入れてしまうというのも一手。
あとは毎日バックアップを取るようにすればよい。
ディスクに保存していた場合でもバックアップは取るので余計な運用コストにはならないだろう。

**結果**

1) HDD

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
| --------- |:----------------------:|:-------:| -------:|
|1000|1.901|0.030|0.028|
|5000|13.857|0.319|0.146|
|10000|74.367|0.924|0.304|
|20000|101.990|4.249|0.621|
|40000|280.950|57.372|4.628|
|60000|598.367|153.301|96.123|

2) tmpfs

| RRD数 | １回目 (ディスクキャッシュなし) sec | 2回目 | 3回目 |
| --------- |:----------------------:|:-------:| -------:|
|1000|0.034|0.024|0.024|
|5000|0.174|0.131|0.129|
|10000|0.359|0.243|0.242|
|20000|0.654|0.495|0.493|
|40000|1.707|1.006|1.000|
|60000|1.672|2.084|2.040|

**結論**

1. ちょっぱやである。他のチューニングが無に帰すレベル。

## まとめ

1. メモリが潤沢にあるならば tmpfs に入れてしまえ(完)
2. SSD が使えるならば使いましょう
3. rrdcached はディスクキャッシュに載ってしまえばあまり効果なし。
4. fadvise は効果あるが、運用が面倒くさすぎるので自分はやりたくない

# 総論

1. Webサイドの高速化

    1. MySQLをチューニングして、--web-max-workers を増やすことで3.3倍の高速化

2. Workerサイドの高速化

    1. --disalble-1min-worker により2倍の高速化 (要[パッチ](https://gist.github.com/sonots/b327a785ba6d4af879b8))
    2. --disable-subtract により5倍の高速化。ディク容量を半分に削減。

3. rrdupdate の高速化

    1. メモリが潤沢にあるならば tmpfs に入れてしまえ(完)
    2. SSD が使えるならば使いましょう
    3. rrdcached はディスクキャッシュに載ってしまえばあまり効果なし。
    4. fadvise は効果あるが、運用が面倒くさすぎるので自分はやりたくない

growthforecast.pl 引数テンプレ

```bash
env MYSQL_USER=growthforecast MYSQL_PASSWORD= perl ./growthforecast.pl \
    --data-dir ./data \
    --port 5125 \
    --disable-1min-metrics \
    --disable-subtract \
    --web-max-workers $NUM_CPU \
    --enable-float-number \
    --with-mysql "dbi:mysql:growthforecast;hostname=localhost" \
```
