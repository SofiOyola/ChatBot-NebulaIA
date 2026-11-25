import { useEffect, useState } from 'react';
import { Keyboard, Platform, type KeyboardEvent } from 'react-native';

export type KeyboardInfo = {
  /** True mientras el teclado está visible. */
  visible: boolean;
  /** Altura del teclado en px de layout (0 si está oculto). */
  height: number;
  /** Coordenada Y (en ventana) del borde SUPERIOR del teclado; Infinity si oculto. */
  top: number;
};

/**
 * Altura real del teclado a partir de los eventos nativos.
 *
 * Por qué no basta `KeyboardAvoidingView` ni `softwareKeyboardLayoutMode: resize`:
 * en Android moderno (Expo SDK 54+, edge-to-edge obligatorio, también en Expo Go)
 * la ventana NO se redimensiona con el teclado; el IME aparece como un "inset".
 * Por eso desplazamos el compositor manualmente con esta altura, en lugar de
 * depender de un resize nativo que no ocurre.
 */
export function useKeyboard(): KeyboardInfo {
  const [info, setInfo] = useState<KeyboardInfo>({ visible: false, height: 0, top: Infinity });

  useEffect(() => {
    // En iOS los eventos *Will* anticipan la animación; en Android se usan *Did*.
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';

    const onShow = (e: KeyboardEvent) => {
      const height = e.endCoordinates?.height ?? 0;
      const top = e.endCoordinates?.screenY ?? Infinity;
      setInfo({ visible: height > 0, height, top });
    };
    const onHide = () => setInfo({ visible: false, height: 0, top: Infinity });

    const showSub = Keyboard.addListener(showEvt, onShow);
    const hideSub = Keyboard.addListener(hideEvt, onHide);
    // Android también puede emitir cambios de métricas (p. ej. teclados que crecen).
    const frameSub =
      Platform.OS === 'android' ? Keyboard.addListener('keyboardDidChangeFrame', onShow) : null;

    return () => {
      showSub.remove();
      hideSub.remove();
      frameSub?.remove();
    };
  }, []);

  return info;
}
