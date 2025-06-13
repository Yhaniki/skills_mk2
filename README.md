# skills_mk2

## 依賴
- Sourcemod 版本：1.11.0.6968  
- Metamod 版本：1.11.0-dev+1155V
- [Left 4 DHooks Direct](https://forums.alliedmods.net/showthread.php?t=321696)
- [L4D2-Competitive-Framework](https://github.com/Attano/L4D2-Competitive-Framework)

## 編譯
+ 進入 `sourcemod/script` 目錄後執行以下指令：

```
spcomp.exe skills_mk2.sp -o ../plugins
```

## 常用指令
```
sm plugins reload skills_mk2
sm plugins refress skills_mk2
sm_version
meta_vertion
```

## 綁定方法
+ 技能指令
    + change_skill 技能清單
    + skill1 施放技能
    + skill2 施放隱藏版爆裂
+ 綁定
    + 遊戲內按`~`打開控制台，輸入綁定按鍵命令
    + bind "按鍵" "指令"
    + 範例
        ```
        bind "x" "change_skill"
        ```
## 目前技能
+ 爆裂: 惠惠的爆裂魔法。
+ 魔心護盾: 使用4MP抵銷1傷害，~~但用近戰武器無傷害。~~
+ 鷹眼: 時間減慢，可以偵查周圍的所有殭屍。
+ 偷竊: 可以對準殭屍或者隊友施放，隨機拿取物品。
+ 淨化: 淨化周圍殭屍，~~施放完後會吸引更多殭屍過來。~~
+ 隱藏版爆裂: 消費100MP使用skill2，施放隱藏版爆裂。施放過程中無敵，~~結束後會因魔力枯竭倒地。~~

## 開發中
- [ ] 惠惠：升級原本的爆裂技能（施放過程中改變天氣狀態）
- [x] 和真：偷竊 → 偷取隊友或者殭屍的物品（完成）
- [x] 阿克婭：淨化 → 殺死周圍殭屍（完成）
- [x] 達克尼斯：魔心護盾（完成）

![人物模型圖片](https://steamuserimages-a.akamaihd.net/ugc/2050869154880058882/DBD4D61BC104B63608AF593F81527625CB9EDBCC/?imw=5000&imh=5000&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false)
