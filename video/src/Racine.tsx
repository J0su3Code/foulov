import { Composition } from "remotion";
import { Film, DUREE } from "./Film";
import "./polices";

export const FPS = 30;

export const Racine = () => (
  <>
    <Composition id="FouLoveVertical" component={Film} width={1080} height={1920} fps={FPS} durationInFrames={Math.ceil(DUREE * FPS)} />
    <Composition id="FouLoveHorizontal" component={Film} width={1920} height={1080} fps={FPS} durationInFrames={Math.ceil(DUREE * FPS)} />
  </>
);
