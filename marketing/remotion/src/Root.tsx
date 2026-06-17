import React from "react";
import { Composition } from "remotion";
import { MarbleAd } from "./MarbleAd";
import { MarbleAdVO } from "./MarbleAdVO";

// All 9:16 vertical at 30fps.
export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="MarbleAd" component={MarbleAd} durationInFrames={1050} fps={30} width={1080} height={1920} />
      {/* Narrated cut: scenes timed to the supplied voiceover SRT (~29s). */}
      <Composition id="MarbleAdVO" component={MarbleAdVO} durationInFrames={870} fps={30} width={1080} height={1920} />
    </>
  );
};
